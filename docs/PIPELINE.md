# Photor, dal clic ai pixel

Questo documento descrive il programma realizzato, non un’architettura futura. Per ogni pezzo trovi una parola che lo riassume e le quattro risposte: **cos’è, da cosa dipende, che relazione c’è e cosa fa in pratica**.

## 1. Il percorso completo

Quando apri una fotografia non ancora pronta:

```text
Tu scegli una cartella
  ↓ il selettore restituisce il suo indirizzo
FolderAccess
  ↓ ViewerModel chiede al motore di aprirla
PhotoPipeline → FolderCatalog
  ↓ il catalogo restituisce una lista ordinata di file
PrefetchPlanner
  ↓ decide quali immagini preparare prima
PriorityWorkQueue
  ↓ consegna le richieste una alla volta
DecodeExecutor
  ↓ fa lavorare al massimo due decoder contemporaneamente
DecoderRegistry
  ├─ JPEG/HEIF/PNG/TIFF → ImageIODecoder → ImageIO
  └─ RAF → RAWDecoder → anteprima ImageIO oppure sviluppo Core Image
  ↓ PixelNormalizer porta il risultato nel formato comune BGRA/sRGB
DecodedImage
  ↓ ImageCache conserva i pixel e una prenotazione di memoria
PhotoPipeline
  ↓ invia un evento: «questa foto è pronta»
ViewerModel
  ↓ chiede di preparare la rappresentazione GPU
TextureCache
  ↓ copia i pixel in una texture Metal
PresentationCache
  ↓ tiene poche texture vicine subito accessibili all’interfaccia
PhotoCanvas → PhotoMetalView → MetalRenderer
  ↓ invia alla GPU le istruzioni per disegnare
PhotoShaders.metal
  ↓ legge i colori della texture e produce i pixel del fotogramma
Metal / driver GPU / GPU
  ↓ consegnano il fotogramma alla superficie della finestra
macOS compone le finestre
  ↓
Display
```

`MemoryBudget` controlla parallelamente le prenotazioni di immagini, texture, upload e lavori. Non è una fase attraversata una volta: viene consultato ogni volta che occorre memoria.

Quando la foto vicina è già pronta, il percorso si accorcia:

```text
Freccia → ViewerModel → PresentationCache → MetalRenderer → schermo
```

Il decoder non viene richiamato. Contatore e riferimento alla nuova texture possono cambiare nello stesso turno dell’interfaccia.

## 2. Chi può usare chi

Una **dipendenza di codice** significa: «questo modulo importa i tipi pubblici di quell’altro». Il **percorso dei dati** indica invece chi passa una richiesta o un risultato a chi durante l’esecuzione.

```text
PhotorApp
  ├── PhotorCore
  ├── PhotorDecoders ──→ PhotorCore
  └── PhotorRendering ─→ PhotorCore

PhotorCore      → Foundation, CoreGraphics, Dispatch
PhotorDecoders  → ImageIO, CoreImage, CoreGraphics, Foundation
PhotorRendering→ Metal, MetalKit, AppKit, CoreGraphics, Foundation
PhotorApp      → SwiftUI, AppKit, Foundation e i tre moduli sopra
```

Core non importa Decoders. Nel Core esiste il contratto `PhotoDecoder`; all’avvio l’app gli passa un `DecoderRegistry` che rispetta quel contratto. È come una presa: il motore conosce il collegamento necessario, mentre l’app sceglie cosa collegare.

In questo modo il motore può chiedere una decodifica senza conoscere i dettagli di ImageIO o dei RAW. I test possono collegare alla stessa presa un decoder finto e lento, per verificare cambi cartella e concorrenza.

## 3. I pezzi dell’app, dall’alto

### PhotorApp.swift — Avvio

- **Cos’è:** il punto d’ingresso dell’eseguibile e il delegato dell’app macOS.
- **Dipende da:** AppKit, SwiftUI e `ViewerModel`.
- **Relazione:** crea una finestra AppKit e le inserisce una vista SwiftUI attraverso `NSHostingView`.
- **In pratica:** avvia Photor, crea menu e scorciatoie, mostra la finestra e chiude il processo quando chiudi l’ultima finestra. Gli argomenti diagnostici attivano le verifiche automatiche.

### AppDependencies — Collegamenti

- **Cos’è:** il posto in cui vengono costruiti e collegati i componenti principali.
- **Dipende da:** dispositivo Metal, decoder, pipeline, budget e cache delle texture.
- **Relazione:** crea un solo budget condiviso e passa lo stesso oggetto al motore e al renderer.
- **In pratica:** decide quali oggetti reali usare e li consegna a chi ne ha bisogno. Evita oggetti globali nascosti.

### ViewerView — Interfaccia

- **Cos’è:** la vista SwiftUI con pulsanti, nome file, contatore e stato della cache.
- **Dipende da:** `ViewerModel`, `PhotoCanvas` e `SettingsView`.
- **Relazione:** legge lo stato del modello e gli invia azioni quando premi un pulsante.
- **In pratica:** mostra `356 / 600`, presenta il caricamento quando necessario e offre i comandi Apri, Adatta e 100%.

### ViewerModel — Regia

- **Cos’è:** lo stato della sessione di visualizzazione, aggiornato sul MainActor.
- **Dipende da:** `AppDependencies`, `FolderAccess`, `ViewerSettings` e dagli eventi della pipeline.
- **Relazione:** traduce le azioni dell’interfaccia in richieste al motore; traduce i risultati del motore in stato visibile.
- **In pratica:** ricorda la foto selezionata, aggiorna il contatore, cerca subito una texture pronta e scarta risultati arrivati per una selezione precedente.

### FolderAccess — Accesso

- **Cos’è:** l’adattatore tra l’app e il selettore cartelle di macOS.
- **Dipende da:** `NSOpenPanel`, URL e UserDefaults.
- **Relazione:** il pannello restituisce un URL; un bookmark permette di ricordare la cartella e provare a riaprirla.
- **In pratica:** apre la finestra di scelta con ⌘O e conserva il riferimento all’ultima cartella. Non copia e non modifica le fotografie.

### SettingsView e ViewerSettings — Preferenze

- **Cos’è:** la finestra delle impostazioni e il codice che le salva.
- **Dipende da:** SwiftUI, `ViewerConfiguration` e UserDefaults.
- **Relazione:** la vista modifica una configurazione; il modello la applica a budget e pipeline; UserDefaults la conserva tra avvii.
- **In pratica:** puoi cambiare memoria massima, distanza di precaching e riempimento del resto della cartella.

## 4. Il motore

### PhotoAsset, PhotoID, FileRevision, PixelSize — Identità

- **Cos’è:** piccoli dati che descrivono una foto, senza contenerne tutti i pixel.
- **Dipende da:** tipi Swift, URL e Date di Foundation.
- **Relazione:** il catalogo li costruisce; motore, cache e interfaccia li usano per parlare della stessa sorgente.
- **In pratica:** `PhotoID` identifica il percorso; `FileRevision` conserva dimensione e data di modifica; `PhotoAsset` collega questi dati all’URL; `PixelSize` esprime larghezza e altezza.

In questa versione ogni file è un elemento: `DSCF0023.JPG` e `DSCF0023.RAF` contano come due foto. Non esiste ancora un raggruppamento automatico degli scatti.

### ImageRepresentation e CacheKey — Etichetta

- **Cos’è:** la descrizione della versione richiesta e la sua chiave nella cache.
- **Dipende da:** identità della sorgente, revisione del file e risoluzione richiesta.
- **Relazione:** una stessa fotografia può avere una versione per lo schermo e una completa, conservate con chiavi diverse.
- **In pratica:** impedisce di confondere un JPEG ridotto a 3072 pixel con l’immagine completa da 7728 pixel. La politica colore è fissa a sRGB in questa versione; se diventasse configurabile andrebbe inclusa nella chiave.

### ViewerConfiguration — Regole

- **Cos’è:** un gruppo di valori numerici e opzioni.
- **Dipende da:** tipi Swift; viene inizializzato dalle preferenze.
- **Relazione:** planner e pipeline leggono queste regole per scegliere quanto precaricare e quanta memoria utilizzare.
- **In pratica:** contiene il budget, il raggio ±100, il raggio del dettaglio completo e la dimensione delle preview.

### FolderCatalog — Elenco

- **Cos’è:** il componente che legge il contenuto della cartella.
- **Dipende da:** FileManager e URL di Foundation.
- **Relazione:** chiede al filesystem nomi e metadati e restituisce un array di `PhotoAsset`.
- **In pratica:** esclude file nascosti e formati non gestiti, poi ordina i nomi in modo naturale: `foto2` prima di `foto10`. Non decodifica le foto e non percorre sottocartelle.

### PhotoPipeline — Coordinamento

- **Cos’è:** un actor che conserva il catalogo, la selezione e lo stato dei lavori.
- **Dipende da:** catalogo, planner, coda, executor, contratto del decoder, cache e budget.
- **Relazione:** collega queste parti e pubblica eventi attraverso `AsyncStream`, un flusso di risultati che l’app ascolta.
- **In pratica:** cerca prima in cache, evita lavori duplicati, avvia quelli mancanti e comunica quali immagini sono pronte. Cambiando cartella incrementa una generazione: i risultati della generazione vecchia vengono ignorati.

### PrefetchPlanner — Priorità

- **Cos’è:** una funzione che prepara un piano di lavoro.
- **Dipende da:** catalogo, indice corrente, direzione e configurazione.
- **Relazione:** legge soltanto dati e restituisce richieste ordinate; non apre file e non crea texture.
- **In pratica:** mette prima la foto corrente, poi le vicine, favorendo la direzione in cui stai andando. Per i RAW limita il dettaglio completo alla corrente e al massimo una vicina per lato.

### PriorityWorkQueue — Coda

- **Cos’è:** il piano ordinato e un indice che indica il prossimo lavoro.
- **Dipende da:** richieste prodotte dal planner.
- **Relazione:** la pipeline estrae richieste; una nuova navigazione sostituisce il piano rimanente.
- **In pratica:** evita di avviare centinaia di decodifiche insieme. Estrarre il prossimo elemento costa O(1); il piano viene riordinato quando cambia la navigazione.

### DecodeExecutor — Lavoratori

- **Cos’è:** un gruppo limitato di operazioni in background.
- **Dipende da:** OperationQueue, `PhotoDecoder`, `DecodeRequest` e `CancellationFlag`.
- **Relazione:** esegue il decoder fuori dall’interfaccia e riconsegna il risultato alla pipeline tramite una continuazione Swift.
- **In pratica:** lascia partire al massimo due decodifiche. Controlla l’annullamento prima e dopo il decoder; una decodifica Apple già avviata non viene interrotta forzatamente a metà.

### PhotoDecoder, DecodeRequest e DecodedImage — Contratto

- **Cos’è:** rispettivamente una regola comune, una richiesta e il risultato della richiesta.
- **Dipende da:** metadati della foto, rappresentazione richiesta e `CGImage` di CoreGraphics.
- **Relazione:** il motore invia una richiesta a un oggetto che rispetta il contratto; quell’oggetto restituisce pixel immutabili e metadati.
- **In pratica:** dice «prepara questa foto per lo schermo» oppure «preparala completa». Il risultato specifica dimensioni, byte occupati, tempo impiegato e se si tratta di un’anteprima RAW.

`CancellationFlag` accompagna il lavoro e registra l’annullamento. `PhotoError` esprime errori leggibili: file non leggibile, decodifica fallita o memoria insufficiente.

## 5. Da file a pixel

### DecoderRegistry — Smistamento

- **Cos’è:** il decoder consegnato al motore dall’app.
- **Dipende da:** `ImageIODecoder`, `RAWDecoder` e dal contratto `PhotoDecoder`.
- **Relazione:** rispetta il contratto comune e delega il lavoro al decoder concreto.
- **In pratica:** un RAF va al percorso RAW; gli altri formati gestiti vanno a ImageIO.

### ImageIODecoder — Decodifica

- **Cos’è:** l’adattatore per JPEG e gli altri formati bitmap supportati.
- **Dipende da:** ImageIO, CoreGraphics e `PixelNormalizer`.
- **Relazione:** ImageIO legge il file, ricostruisce i pixel e applica ridimensionamento e orientamento EXIF; il normalizzatore uniforma il formato risultante.
- **In pratica:** un JPEG da 15,9 MB diventa una preview già decodificata oppure un’immagine completa. Il lavoro avviene prima della visualizzazione, non durante il gesto di zoom.

### RAWDecoder — Sviluppo

- **Cos’è:** l’adattatore per i RAF.
- **Dipende da:** ImageIO per l’anteprima e da `CIRAWFilter`/`CIContext` di Core Image per lo sviluppo.
- **Relazione:** prova prima a estrarre un’anteprima; per il dettaglio completo interpreta i dati del sensore e li rende come immagine a colori.
- **In pratica:** nel tuo campione trova un’anteprima da 4416 × 2944 e può sviluppare 7728 × 5152 pixel. Crea un filtro separato per ogni lavoro e riutilizza il contesto di rendering.

L’anteprima può avere il look della macchina. Lo sviluppo Apple può cambiarne colori e contrasto. Questa versione non è un editor RAW e non replica le ricette Fujifilm.

### PixelNormalizer — Uniformità

- **Cos’è:** la funzione interna che produce il formato comune dei pixel.
- **Dipende da:** CGContext e CGColorSpace di CoreGraphics.
- **Relazione:** disegna l’immagine decodificata in un buffer BGRA a 8 bit per canale, nello spazio colore sRGB.
- **In pratica:** i decoder possono restituire immagini diverse; dopo questa fase il renderer sa sempre come leggere i byte. Il disegno forza anche la materializzazione dei pixel.

BGRA significa quattro byte per pixel: blu, verde, rosso e trasparenza. Una foto da 7728 × 5152 occupa circa 159 MB in questo formato. Questa prima versione visualizza in SDR a 8 bit: non è una pipeline HDR o di editing a 16 bit.

## 6. Dove rimangono le immagini

### ImageCache — Magazzino

- **Cos’è:** un dizionario di immagini decodificate, accessibile soltanto dalla pipeline.
- **Dipende da:** `CacheKey`, `CachedImage` e dalle priorità della navigazione.
- **Relazione:** il motore cerca e inserisce immagini; quando serve spazio, sceglie quali riferimenti rimuovere.
- **In pratica:** conserva anche foto uscite dalla finestra ±100. Sotto pressione elimina prima quelle meno prioritarie, usando l’uso recente per risolvere i casi equivalenti. Una richiesta lontana non deve espellere una foto più utile.

La ricerca nel dizionario è mediamente O(1). La scelta di una vittima scorre le voci solo quando serve liberare memoria: è una scelta semplice per questa dimensione di cache.

### MemoryBudget — Contabilità

- **Cos’è:** un contatore condiviso con un limite.
- **Dipende da:** NSLock e numeri interi; non dipende dall’interfaccia.
- **Relazione:** pipeline e cache delle texture chiedono una prenotazione prima di impegnare risorse.
- **In pratica:** registra separatamente immagini, texture, upload e riserve dei lavori. Rifiuta una nuova prenotazione che supererebbe il limite.

Le immagini decodificate usano al massimo circa il 60% del budget gestito, lasciando spazio a GPU e lavoro temporaneo. Il riempimento facoltativo della cartella rallenta prima di raggiungere quel tetto. Le riserve temporanee iniziali sono conservative: 512 MiB per i lavori ordinari, 1 GiB per uno sviluppo RAW completo.

Il budget non è una misura esatta della memoria totale del processo: macOS e i framework possono allocare altre strutture interne. L’indicatore RAM dell’app rappresenta le risorse gestite e le prenotazioni, non il numero di Monitoraggio Attività.

### MemoryLease e CachedImage — Possesso

- **Cos’è:** una prenotazione di byte e il contenitore che collega un’immagine alla sua prenotazione.
- **Dipende da:** `MemoryBudget` e dalla gestione dei riferimenti Swift, chiamata ARC.
- **Relazione:** chi mantiene l’immagine mantiene anche la prenotazione. Le riserve di lavoro si rilasciano esplicitamente al termine; quelle dei dati persistenti seguono la vita degli oggetti.
- **In pratica:** togliere una voce dalla cache non dichiara falsamente libera la memoria se un altro componente sta ancora usando quell’immagine.

### Pressione sulla memoria — Riduzione

- **Cos’è:** la segnalazione di macOS che il sistema sta facendo fatica a soddisfare le richieste di memoria.
- **Dipende da:** `DispatchSourceMemoryPressure`.
- **Relazione:** Dispatch avvisa la pipeline; la pipeline riduce il budget e il precaching e chiede all’app di alleggerire le texture.
- **In pratica:** la cache si restringe automaticamente. L’interfaccia mostra l’avviso con l’icona della memoria. Applicare nuovamente le impostazioni ripristina il budget scelto dall’utente.

Conservare un oggetto non obbliga macOS a tenere ogni pagina fisicamente residente: il sistema può comprimere memoria o usare swap. La strategia è mantenere margine, non bloccare tutta la RAM.

## 7. Dai pixel allo schermo

### TextureCache e TextureFrame — Preparazione

- **Cos’è:** una cache di risorse che la GPU può leggere direttamente.
- **Dipende da:** Metal, immagini decodificate, `MemoryBudget` e una coda di upload seriale.
- **Relazione:** crea una texture, vi copia i pixel e restituisce un `TextureFrame` che conserva texture e prenotazione.
- **In pratica:** anticipa il trasferimento necessario prima del disegno. Riunisce richieste duplicate e conserva fino a otto voci nella propria cache, proteggendo la foto corrente quando elimina le altre.

La dimensione prenotata viene chiesta a Metal: allineamenti e organizzazione della texture possono richiedere più byte di `larghezza × altezza × 4`. Le texture usano memoria condivisa, ma questa implementazione effettua comunque una copia dai pixel decodificati alla texture.

### PresentationCache — Immediatezza

- **Cos’è:** una piccola cache accessibile direttamente dal thread dell’interfaccia.
- **Dipende da:** `TextureFrame`, identità della foto e revisione del file.
- **Relazione:** mantiene al massimo sei riferimenti a texture già preparate, senza copiare i pixel e senza creare una seconda prenotazione per lo stesso oggetto.
- **In pratica:** premendo una freccia la UI può prendere subito la foto vicina. Il budget resta impegnato finché questi riferimenti sono vivi, anche se la cache delle texture elimina la propria voce.

### PhotoCanvas — Ponte

- **Cos’è:** un `NSViewRepresentable`, cioè il collegamento tra SwiftUI e una vista AppKit.
- **Dipende da:** `ViewerModel` e `PhotoMetalView`.
- **Relazione:** SwiftUI gli passa lo stato corrente; lui aggiorna il riferimento alla texture dentro il renderer.
- **In pratica:** mette la superficie Metal nella finestra SwiftUI e collega i cambi di dimensione, lo zoom e la navigazione.

### PhotoMetalView — Gesti

- **Cos’è:** la vista AppKit basata su MTKView.
- **Dipende da:** AppKit, MetalKit, `MetalRenderer` e `ViewportState`.
- **Relazione:** AppKit consegna eventi di trackpad, mouse e tastiera; la vista aggiorna la trasformazione oppure richiama la navigazione.
- **In pratica:** riceve il pinch, sposta una foto ingrandita, gestisce doppio clic e frecce e richiede un nuovo disegno quando occorre.

### ViewportState — Inquadratura

- **Cos’è:** pochi numeri: ingrandimento e spostamento orizzontale/verticale.
- **Dipende da:** dimensioni della vista e punto del gesto.
- **Relazione:** i gesti modificano questi numeri; il renderer li usa per posizionare la foto.
- **In pratica:** ingrandisce attorno al punto sotto il cursore. Non crea una nuova immagine per ogni movimento del trackpad.

### MetalRenderer — Disegno

- **Cos’è:** il codice che prepara un fotogramma per la GPU.
- **Dipende da:** texture, viewport, MTKView, coda di comandi Metal e shader.
- **Relazione:** calcola un rettangolo formato da due triangoli, associa la texture e invia un comando di rendering.
- **In pratica:** adatta la foto alla finestra, applica zoom e spostamento e presenta il fotogramma. Disegna quando cambia qualcosa, senza un ciclo continuo di rendering a finestra ferma.

Il comando GPU trattiene il `TextureFrame` fino al completamento. Così la cache può cambiare senza liberare una texture che la GPU sta ancora leggendo.

### PhotoShaders.metal — Colore

- **Cos’è:** due piccoli programmi eseguiti dalla GPU.
- **Dipende da:** vertici del rettangolo e texture fotografica.
- **Relazione:** il vertex shader posiziona il rettangolo; il fragment shader legge dalla texture il colore necessario a ciascun punto disegnato.
- **In pratica:** la GPU riempie la foto sullo schermo. I formati sRGB fanno gestire a Metal le conversioni previste tra valori memorizzati e calcoli del campionamento.

Lo shader viene compilato da Metal all’avvio. Il file è incluso nelle risorse dell’app: non serve il compilatore Metal separato di Xcode completo per costruire questa prima versione.

## 8. Le fondamenta Apple e l’hardware

| Componente, in una parola | Cos’è | Da cosa dipende | Relazione e lavoro concreto |
|---|---|---|---|
| SwiftUI — Layout | La libreria per descrivere l’interfaccia | Runtime Swift e sistema grafico macOS | Trasforma lo stato del modello in testi, pulsanti e viste. In Photor è ospitata in una finestra AppKit. |
| AppKit — Finestra | La libreria desktop di macOS | Servizi di finestre ed eventi del sistema | Crea la finestra e il pannello cartelle; consegna click, tasti e gesti alla vista giusta. |
| Foundation — Servizi | URL, file, date, preferenze, code e lock | Servizi del sistema operativo | Elenca i file, salva impostazioni e fornisce strumenti per coordinare i lavori. |
| ImageIO — Lettura | Il framework che legge formati immagine | Codec e servizi Apple | Interpreta JPEG, metadati e anteprime e restituisce un’immagine. Le implementazioni interne dei codec restano Apple. |
| Core Image — Sviluppo | Il framework che elabora immagini e RAW | Decoder RAW, CPU/GPU e driver Apple | Ricostruisce un’immagine a colori dai dati del sensore e la rende in un buffer. |
| CoreGraphics — Pixel | Il framework per immagini, colori e disegno bitmap | Allocazioni di memoria e gestione colore Apple | Fornisce CGImage e CGContext; uniforma i pixel e lo spazio colore. |
| Dispatch/OperationQueue — Esecuzione | Gli strumenti per distribuire lavoro | Scheduler e thread del sistema | Fanno avanzare i decoder in background e notificano la pressione sulla memoria. |
| MetalKit — Superficie | Il collegamento pratico tra una vista e Metal | AppKit e Metal | MTKView fornisce dimensioni in pixel e la superficie su cui produrre il prossimo fotogramma. |
| Metal — Comandi | L’interfaccia di programmazione della GPU | Driver e GPU Apple | Crea texture, compila shader e mette in coda il disegno. |
| Driver — Traduzione | Il software del sistema che controlla la GPU | macOS e hardware GPU | Traduce e coordina i comandi Metal con le capacità del chip. |
| Runtime Swift/ARC — Durata | I servizi che supportano il codice Swift e i suoi oggetti | Sistema operativo e memoria del processo | Mantengono vivi gli oggetti usati e li rilasciano quando non servono più. |
| CPU — Istruzioni | I core di calcolo generali | Programma compilato e memoria | Eseguono navigazione, pianificazione, copie e parte della decodifica. |
| GPU — Parallelismo | I core grafici | Comandi, shader e texture in memoria | Calcolano molti pixel insieme e producono il fotogramma. |
| RAM unificata — Spazio | Memoria fisica condivisa da CPU e GPU | Hardware e gestore della memoria macOS | Contiene pixel, texture, metadati e buffer. Condivisione fisica non significa che tutte le rappresentazioni coincidano. |
| Filesystem/SSD — Archivio | I file conservati sul disco | Sistema operativo e dispositivo di archiviazione | Restituiscono i byte del JPEG/RAF quando il decoder li richiede. macOS può avere già parte dei file nella propria cache. |
| Compositore/display — Uscita | Il sistema che compone le finestre e il pannello che le mostra | Fotogrammi, WindowServer e hardware del display | Unisce il contenuto dell’app alle altre finestre e lo invia allo schermo. |

Il dettaglio privato dentro i decoder e driver Apple non è codice di Photor: il programma usa i contratti pubblici dei framework. Il confine più basso controllato direttamente da Photor è costituito da buffer di pixel, texture, vertici e shader.

## 9. Che cosa succede tra memoria e componenti

1. **SSD → decoder:** il sistema legge i byte compressi o RAW. Photor non crea una seconda cache permanente dei file compressi.
2. **Decoder → buffer:** il decoder ricostruisce i colori. Il normalizzatore produce pixel BGRA/sRGB, sostenendo anche allocazioni temporanee.
3. **Buffer → ImageCache:** la cache conserva un riferimento all’immagine e la relativa prenotazione di memoria.
4. **ImageCache → TextureCache:** il caricatore legge i pixel e li copia nella texture. Durante questa fase possono coesistere immagine, dati temporanei e texture.
5. **TextureCache → PresentationCache/UI:** vengono passati riferimenti allo stesso `TextureFrame`, non altre copie dei pixel.
6. **Texture → GPU:** lo shader legge i colori e scrive il fotogramma della finestra. Zoom e pan cambiano la geometria.
7. **GPU → rilascio:** completato il comando, il renderer lascia andare il riferimento usato da quel fotogramma. La memoria torna disponibile quando non restano altri proprietari.

Un actor protegge lo stato della pipeline; i lock del budget proteggono solo aggiornamenti brevissimi dei contatori. Nessun lock del budget resta occupato mentre si legge un file o si sviluppa un RAW. I risultati che attraversano i componenti sono immutabili.

## 10. Gerarchia dei file e strumenti

```text
photor/
├── Package.swift                 eseguibile e collegamento al package locale
├── App/
│   ├── PhotorApp.swift            avvio AppKit, finestra SwiftUI e menu
│   ├── AppDependencies.swift      costruzione dei componenti
│   ├── Features/Viewer/           interfaccia, modello e ponte Metal
│   ├── Features/Settings/         preferenze
│   ├── Features/Albums/           pulsanti, gestione, persistenza e filtri
│   ├── Features/Grid/             griglia e salto numerico
│   ├── Features/Files/            conferme, trasferimento e avanzamento
│   ├── Platform/FolderAccess.swift
│   ├── Platform/ViewState.swift   compatibilità State con i Command Line Tools
│   ├── SmokeCheck.swift           verifica decoder e texture sui file reali
│   ├── FeatureSmokeCheck.swift    nuove funzioni su 1005 JPEG temporanei
│   └── UISmokeCheck.swift         verifica automatica della finestra
├── Packages/PhotorKit/
│   ├── Package.swift              tre librerie e programma delle verifiche
│   ├── Sources/
│   │   ├── PhotorCore/            Models, Catalog, Pipeline, Cache, Prefetch, Albums, Files
│   │   ├── PhotorDecoders/        ImageIODecoder, RAWDecoder, DecoderRegistry
│   │   └── PhotorRendering/       viste Metal, cache, viewport e shader
│   └── Tests/PhotorCoreTests/     controlli autonomi, senza framework di test esterni
├── Resources/Info.plist          identità e proprietà dell’app macOS
├── scripts/build-app.sh          costruzione e firma locale del bundle
├── scripts/test.sh               compilazione ed esecuzione dei controlli
├── docs/PIPELINE.md              questo documento
├── README.md                    avvio e comandi
├── media/                       fotografie locali di prova
└── dist/Photor.app               programma pronto da aprire
```

| Strumento, in una parola | Cos’è | Dipende da | Relazione e azione pratica |
|---|---|---|---|
| Package.swift — Mappa | Il manifesto dei moduli | Swift Package Manager | Dichiara sorgenti, dipendenze, risorse e versione minima macOS. |
| Compilatore — Costruzione | Gli strumenti Swift del Mac | SDK Apple e linker | Trasformano i file Swift in codice macchina e collegano i framework necessari. |
| build-app.sh — Confezione | Lo script di distribuzione locale | Build release, Info.plist, risorse e codesign | Mette eseguibile e shader dentro una `.app` e la firma localmente. |
| PhotorChecks — Controllo | Un piccolo eseguibile di verifiche | Core, decoder JPEG e immagini sintetiche | Verifica budget, priorità, eliminazione, EXIF e risultati obsoleti. Usa un decoder finto per riprodurre ritardi controllati. |
| SmokeCheck — Campioni | La modalità diagnostica senza finestra | Decoder reali e Metal | Legge JPEG/RAF, verifica pixel non vuoti e crea le texture GPU. |
| UISmokeCheck — Percorso | La modalità diagnostica con finestra | App e tutti i moduli | Prova contatore, navigazione, zoom, cache immediata e presentazione GPU; poi chiude il programma. |

Il package delle verifiche usa un eseguibile autonomo perché i Command Line Tools di questo ambiente non dispongono di un runtime XCTest/Swift Testing completo e utilizzabile. Non introduce dipendenze di terze parti.

## 11. Confini della prima versione

- Il catalogo viene aggiornato quando apri o riapri la cartella; non c’è ancora un osservatore delle modifiche del filesystem.
- I RAW sono supportati quando il decoder Apple installato riconosce quel file. Il campione X-T50 fornito è stato sviluppato correttamente.
- La navigazione da cache evita lettura, decodifica e upload nel percorso immediato. Aprire una foto ancora fuori cache richiede comunque lavoro.
- Il riempimento della cartella è progressivo e subordinato al budget; una cartella molto grande non entra magicamente tutta in RAM.
- I controlli automatici usano i due campioni e fixture sintetiche. Non sostituiscono una misura prolungata su una cartella reale di centinaia di scatti.
- Visualizzazione e album non cambiano gli originali. Le azioni esplicite Cestino, Copia e Sposta lavorano sui file; non modificano i pixel.

## 12. Album, griglia e file — versione 0.2

Le nuove funzioni riusano lo stesso motore di visualizzazione. Il Core continua a non conoscere SwiftUI o AppKit.

```text
Clic su stella / icona
  → AlbumButtons → ViewerModel+Albums → AlbumLibrary
  → AlbumStore → JSONEncoder → scrittura atomica Foundation → filesystem / SSD

Apri un album
  → AlbumMenu → ViewerModel+Albums → AlbumLibrary.resolve
  → URL legge i metadati dei percorsi salvati → lista ordinata di PhotoAsset
  → PhotoPipeline.setCatalog → stessa pipeline decoder / cache / Metal di prima

Apri la griglia e scorri
  → PhotoGrid / LazyVGrid → celle visibili → ThumbnailCache
  → DecodeExecutor → DecoderRegistry → ImageIO (anche anteprima RAF)
  → CGImage da massimo 512 pixel → cache con MemoryLease → immagine SwiftUI

Premi Cestino e conferma
  → ViewerModel+Files → PhotoFileService → controllo aggiornato del file
  → FileManager.trashItem → Cestino macOS
  → rimozione dei percorsi dagli album → salvataggio → nuovo catalogo

Trasferisci un album
  → AlbumTransferView → FolderAccess / NSOpenPanel → destinazione
  → ViewerModel+Files → PhotoFileService → un file alla volta
  → FileManager.copyItem oppure moveItem → filesystem / SSD
  → risultato per file → progressione nell’interfaccia
  → se spostato: aggiorna tutti gli album → salvataggio → file successivo
  → rapporto finale → aggiornamento catalogo e cache
```

| Componente, in una parola | Cos’è | Dipende da | Relazione e azione concreta |
|---|---|---|---|
| AlbumButtons / AlbumMenu / AlbumManagerView — Comandi | Le viste per classificare e aprire le raccolte | SwiftUI e ViewerModel | Inviano aggiungi/rimuovi, crea, rinomina e apri; il modello restituisce icone, nomi e conteggi. |
| ViewerModel+Albums — Regia | La parte del modello dedicata agli album | AlbumLibrary, AlbumStore e PhotoPipeline | Cambia appartenenze, salva e sostituisce il catalogo con la lista dell’album scelto. |
| PhotoAlbum / AlbumLibrary — Elenco | Strutture di dati senza pixel | UUID, String, Set e URL di Foundation | Ogni album contiene un identificativo stabile, nome, icona e insieme di percorsi; controlla nomi e limite di quattro custom. |
| AlbumStore — Persistenza | Un actor che legge e salva l’archivio | Codable, JSONEncoder/Decoder, Data e FileManager | Serializza su disco e impedisce a un salvataggio vecchio di sostituirne uno più recente; un archivio illeggibile non viene sovrascritto automaticamente. |
| PhotoGrid / ThumbnailCell — Mosaico | Griglia adattiva di riquadri quadrati | SwiftUI, PhotoAsset e ThumbnailCache | Richiede le miniature per le celle mostrate, annulla i lavori delle celle uscite e passa al visualizzatore quando clicchi. |
| JumpToPhotoView — Salto | Un campo numerico | ViewerModel e ScrollViewReader | Controlla 1…totale, cambia selezione e porta la griglia al riquadro corrispondente. |
| ThumbnailCache — Miniature | Cache separata dalle immagini grandi | Decoder, DecodeExecutor, MemoryBudget, CacheKey | Usa due worker, precedenza alle richieste più recenti, massimo 512 pixel e rimuove le miniature meno usate. |
| AlbumTransferView — Destinazione | La finestra Copia/Sposta | SwiftUI, FolderAccess e ViewerModel | Mostra destinazione, effetto dell’operazione, conferma dello spostamento, avanzamento e file falliti. |
| ViewerModel+Files — Operazione | Il coordinamento delle modifiche ai file | PhotoFileService, album e pipeline | Sospende il precaching, riceve gli esiti, aggiorna i percorsi e rilegge la raccolta. |
| PhotoFileService — Trasporto | Servizio senza interfaccia per singoli file e lotti | FileManager, URL, FileRevision e CancellationFlag | Rilegge dimensione/data senza metadati in cache, rifiuta sorgenti cambiate, sceglie nomi liberi, copia/sposta oppure usa il Cestino. |
| TransferUpdate / TransferReport — Esito | Dati immutabili passati tra background e UI | URL, contatori e messaggi | Distinguono successi e fallimenti; permettono di annullare tra due file senza fingere che quelli già trasferiti siano tornati indietro. |
| ViewState — Compatibilità | Un alias del tipo SwiftUI.State | SwiftUI | Evita che l’SDK macOS 27 scelga l’omonima macro senza plugin nei Command Line Tools; il comportamento resta quello del normale property wrapper. |

I percorsi degli album sono un `Set<String>`: aggiungere, togliere e verificare appartenenze costa mediamente O(1), senza duplicati. L’array del catalogo serve invece a mantenere ordine e indice. Gli album conservano solo riferimenti, quindi mille stelle non duplicano mille fotografie in RAM o su disco.

La cache miniature punta a un massimo di 256 MiB o un sedicesimo del budget globale, se inferiore; le celle ancora visibili trattengono le proprie immagini. Anche i due lavori delle miniature prenotano memoria nello stesso budget. In griglia la pipeline principale prepara solo la preview della selezione, mentre mette in pausa il precaching delle immagini grandi. Tornando alla foto lo riattiva. Il limite di due worker vale per ciascuna coda: lavori della vecchia vista già avviati possono terminare durante il passaggio.

Il trasferimento gira fuori dal MainActor. I comandi che cambiano raccolta e i trasferimenti simultanei sono disabilitati fino alla conclusione. Annulla si ferma dopo il file in corso; chiudere l’app durante l’operazione viene impedito. Se il salvataggio dei nuovi percorsi fallisce, lo spostamento si ferma dopo il file corrente e mostra l’errore; il modello conserva i riferimenti aggiornati per riprovare il salvataggio.

Gli album vengono salvati dopo ogni spostamento riuscito. File e JSON sono due operazioni distinte: un arresto improvviso tra lo spostamento fisico e il salvataggio può lasciare un riferimento al vecchio percorso. Non c’è ancora un giornale di recupero per questo intervallo. L’eliminazione passa esclusivamente dal Cestino del sistema; se macOS non riesce a cestinare, Photor mostra l’errore e non tenta una cancellazione definitiva.

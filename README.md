# Photor

Visualizzatore nativo macOS per sfogliare foto grandi con precaching in RAM. Swift, SwiftUI/AppKit, ImageIO, Core Image e Metal; nessuna dipendenza esterna da scaricare.

## Avvio

Apri **`dist/Photor.app`** e scegli una cartella con **⌘O**, oppure trascina la cartella sulla finestra. Puoi spostare l’app in Applicazioni: contiene anche le risorse del renderer.

Su macOS la `.app` è il programma avviabile con doppio clic. Per ricrearla, dalla cartella del progetto esegui `bash scripts/build-app.sh`, poi `open dist/Photor.app`. La build converte automaticamente `Photor logo.png` nelle dimensioni standard/Retina, crea l’icona `.icns`, la inserisce nel bundle e firma l’app. Per aggiornare il logo basta sostituire quel PNG e ripetere il comando. I file intermedi dell’icona rimangono in `.build/`, esclusa da Git.

| Comando | Risultato |
|---|---|
| ← / → | Foto precedente / successiva |
| Pinch sul trackpad | Zoom attorno al punto del gesto |
| Due dita sul trackpad, a foto ingrandita | Spostamento nella foto |
| Trascinamento con il mouse | Spostamento nella foto |
| Doppio clic | Passa da adattamento a dimensione reale |
| Spazio / pulsante Adatta | Mostra tutta la foto |
| 1 / pulsante 100% | Un pixel della foto per pixel fisico del display |
| + / − oppure ⌘ + rotella | Zoom |
| ⌘, | Impostazioni cache |
| ⌃⌘F | Schermo intero |
| ⌘S | Aggiungi/rimuovi la foto dai Preferiti |
| ⌘1…⌘4 | Aggiungi/rimuovi dai quattro album personalizzati |
| ⌥⌘S | Apri Preferiti |
| ⇧⌘A | Crea, rinomina o rimuovi album |
| ⌘G | Passa tra foto e griglia |
| ⌘J | Vai direttamente a un numero di foto |
| ⌘⌫ | Sposta nel Cestino, previa conferma |
| ⇧⌘E | Copia/sposta l’album aperto |

La prima versione legge i file direttamente nella cartella, senza sottocartelle. JPEG e RAF con lo stesso nome sono due elementi separati. Per rileggere una cartella modificata, riaprila con ⌘O.

Il budget iniziale sul Mac da 64 GB è 16 GiB, regolabile tra 4 e 32 GiB. La finestra di precaching iniziale è ±100 immagini; il dettaglio completo viene preparato per la corrente e fino a ±5 JPEG, ±1 RAF. La cache conserva le immagini più lontane quando c’è spazio. Il budget prevale sul numero richiesto.

Per i RAW vengono mostrate prima le anteprime disponibili, poi lo sviluppo completo Apple. Il loro aspetto può differire dal JPEG Fujifilm. La visualizzazione e le stelle non modificano gli originali.

## Album, griglia e trasferimenti

In alto a destra trovi la stella e, inizialmente, il segnalibro per **Selezione**. Le icone accese indicano gli album della foto corrente. Dal menu sotto la barra superiore puoi aprire gli album e gestirli: un album Preferiti fisso e fino a quattro personalizzati con icone distinte. Sono raccolte virtuali persistenti e possono contenere foto di cartelle diverse; creare o rimuovere un album non copia né elimina file.

La griglia carica piccole miniature per le celle mostrate. Puoi scorrerla, aprire una foto con un clic oppure usare **Vai alla foto…** per raggiungere, ad esempio, la numero 1000. Gli stessi comandi funzionano all’interno degli album. Il menu contestuale di una miniatura permette di cambiare album o cestinare quel file.

**Trasferisci album…** permette di scegliere una destinazione e **Copia** o **Sposta**. Copia lascia gli originali e i riferimenti degli album al loro posto. Sposta trasferisce i file e aggiorna i percorsi in tutti gli album; richiede conferma. I file omonimi ricevono un suffisso numerico e non vengono sovrascritti. L’annullamento si applica dopo il file corrente: i trasferimenti già completati restano validi. Gli eventuali errori sono elencati nella finestra.

Il pulsante Cestino usa il Cestino di macOS e rimuove il file da tutti gli album. Recuperarlo con Finder ripristina il file, non le precedenti appartenenze agli album. JPEG e RAF rimangono elementi indipendenti anche per queste operazioni: non vengono ricompressi o convertiti.

L’archivio degli album è `~/Library/Application Support/Photor/albums.json`, salvato atomicamente. File spostati da Photor conservano le appartenenze. File rinominati o spostati da Finder, o su dischi scollegati, vengono segnalati come mancanti; non è ancora presente il ritrovamento automatico. I trasferimenti riguardano le foto disponibili nell’album aperto.

## Struttura spiegata

Leggi **[docs/PIPELINE.md](docs/PIPELINE.md)**: segue una foto dal file fino allo schermo. Ogni componente ha una parola riassuntiva e quattro risposte: cos’è, da cosa dipende, che rapporto ha con le dipendenze e cosa fa in pratica.

## Compilazione e verifiche

Servono gli strumenti Swift 6 di Xcode oppure i Command Line Tools. L’app dichiara macOS 14 come minimo; le verifiche della versione 0.2 sono eseguite con Swift 6.4 su macOS 27.0.1, Apple M5 Pro. Il supporto RAW dipende dai decoder installati con macOS. Gli script individuano il percorso dei prodotti anche con il nuovo sistema di build di Swift.

```sh
bash scripts/build-app.sh
bash scripts/test.sh

# Verifica i decoder e gli upload alla GPU sui campioni locali.
dist/Photor.app/Contents/MacOS/Photor --smoke-test "$PWD/media"

# Apre una finestra temporanea, prova la navigazione e lo zoom, poi termina.
dist/Photor.app/Contents/MacOS/Photor --ui-test --folder "$PWD/media"

# Album, griglia, copia/spostamento e Cestino: usa solo file sintetici temporanei.
dist/Photor.app/Contents/MacOS/Photor --features-test
```

`scripts/test.sh` esegue controlli autonomi, senza richiedere il runtime XCTest. Il test UI richiede i due campioni JPEG/RAF e una sessione desktop. Produce immagini diagnostiche in `/private/tmp`, mai nella cartella delle fotografie.

La build è firmata localmente, senza notarizzazione per distribuzione pubblica. `media/`, `.build/` e `dist/` sono esclusi dal versionamento tramite `.gitignore`.

# Photor

Visualizzatore nativo macOS per sfogliare foto grandi con precaching in RAM. Swift, SwiftUI/AppKit, ImageIO, Core Image e Metal; nessuna dipendenza esterna da scaricare.

## Avvio

Apri **`dist/Photor.app`** e scegli una cartella con **⌘O**, oppure trascina la cartella sulla finestra. Puoi spostare l’app in Applicazioni: contiene anche le risorse del renderer.

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

La prima versione legge i file direttamente nella cartella, senza sottocartelle. JPEG e RAF con lo stesso nome sono due elementi separati. Per rileggere una cartella modificata, riaprila con ⌘O.

Il budget iniziale sul Mac da 64 GB è 16 GiB, regolabile tra 4 e 32 GiB. La finestra di precaching iniziale è ±100 immagini; il dettaglio completo viene preparato per la corrente e fino a ±5 JPEG, ±1 RAF. La cache conserva le immagini più lontane quando c’è spazio. Il budget prevale sul numero richiesto.

Per i RAW vengono mostrate prima le anteprime disponibili, poi lo sviluppo completo Apple. Il loro aspetto può differire dal JPEG Fujifilm. Gli originali vengono soltanto letti.

## Struttura spiegata

Leggi **[docs/PIPELINE.md](docs/PIPELINE.md)**: segue una foto dal file fino allo schermo. Ogni componente ha una parola riassuntiva e quattro risposte: cos’è, da cosa dipende, che rapporto ha con le dipendenze e cosa fa in pratica.

## Compilazione e verifiche

Servono gli strumenti Swift 6 di Xcode oppure i Command Line Tools. L’app dichiara macOS 14 come minimo; le verifiche locali sono eseguite su macOS 26.6.2, Apple M5 Pro. Il supporto RAW dipende dai decoder installati con macOS.

```sh
bash scripts/build-app.sh
bash scripts/test.sh

# Verifica i decoder e gli upload alla GPU sui campioni locali.
dist/Photor.app/Contents/MacOS/Photor --smoke-test "$PWD/media"

# Apre una finestra temporanea, prova la navigazione e lo zoom, poi termina.
dist/Photor.app/Contents/MacOS/Photor --ui-test --folder "$PWD/media"
```

`scripts/test.sh` esegue controlli autonomi, senza richiedere il runtime XCTest. Il test UI richiede i due campioni JPEG/RAF e una sessione desktop. Produce immagini diagnostiche in `/private/tmp`, mai nella cartella delle fotografie.

La build è firmata localmente, senza notarizzazione per distribuzione pubblica. `media/`, `.build/` e `dist/` sono esclusi dal versionamento tramite `.gitignore`.

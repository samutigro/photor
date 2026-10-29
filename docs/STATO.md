# Stato della versione 0.2 — 29 ottobre 2026

## Consegna

App compilata e firmata localmente in `dist/Photor.app`. Comandi e utilizzo in [README.md](../README.md); struttura e dipendenze, comprese le nuove pipeline, in [PIPELINE.md](PIPELINE.md).

## Aggiunte

1. Preferiti con stella, un album iniziale Selezione e fino a quattro album personalizzati: nomi, icone distinte, scorciatoie e persistenza fra avvii. Gli album possono contenere file di cartelle diverse.
2. Griglia di miniature quadrate caricate progressivamente, con due worker dedicati e budget condiviso. Salto diretto a un numero di foto, anche negli album.
3. Cestino macOS con conferma; aggiorna catalogo, selezione e appartenenze agli album. Nessuna cancellazione definitiva come ripiego.
4. Copia o spostamento dell’album nella destinazione scelta: avanzamento, annullamento dopo il file corrente, nomi omonimi preservati con suffissi, errori per file e aggiornamento persistente dei percorsi dopo ogni spostamento.

Navigazione, zoom, renderer Metal, supporto JPEG/RAF e precaching della versione precedente rimangono disponibili. Ogni JPEG o RAF è un elemento indipendente. Il trasferimento conserva il formato originale.

L’archivio è `~/Library/Application Support/Photor/albums.json`. La scrittura è atomica e i salvataggi obsoleti vengono ignorati. Un archivio illeggibile viene segnalato senza sostituirlo automaticamente.

## Verifiche

- Otto gruppi di controlli del motore: budget, planner, eviction, catalogo/EXIF/colore, concorrenza, album/persistenza, trasferimenti/collisioni/annullamento e miniature/cancellazione/rilascio memoria.
- Prova UI dedicata su 1.005 JPEG sintetici: album, persistenza, selezione dopo rimozione, salto alla foto 1000, caricamento limitato delle miniature, copia, spostamento, aggiornamento percorsi e Cestino nativo. Usa un archivio album isolato e recupera il file temporaneo dal Cestino prima della pulizia.
- Verifica separata dei decoder JPEG e RAF sui campioni reali, con upload e disegno Metal; prova UI di navigazione, contatore, zoom e ritorno dalla cache.
- Catture diagnostiche della griglia e del renderer in `/private/tmp`.

Ambiente: Apple M5 Pro, macOS 27.0.1, Swift 6.4. La compatibilità dichiarata è macOS 14+, ma questa revisione non è stata eseguita sui sistemi precedenti. Gli script supportano il percorso dei prodotti del nuovo sistema di build Swift; `ViewState` gestisce la collisione con la macro State dell’SDK 27 nei Command Line Tools.

## Limiti e prossime valutazioni

- Le 1.005 immagini sintetiche verificano griglia, indici e operazioni; non misurano il precaching di mille JPEG differenti da 20 MB. Serve ancora una prova prolungata su una tua cartella reale e sotto carico di memoria.
- Restano da valutare manualmente la sensibilità del trackpad e i monitor esterni.
- Modifiche fatte da Finder richiedono la riapertura della cartella. Non ci sono ricerca ricorsiva, raggruppamento JPEG+RAF o ritrovamento automatico di file rinominati/spostati fuori da Photor. Dischi scollegati e file mancanti vengono segnalati negli album.
- Un’interruzione improvvisa tra spostamento fisico e salvataggio JSON può lasciare il vecchio percorso nell’archivio: non è ancora presente un giornale di recupero. Durante il normale uso l’app blocca la chiusura mentre trasferisce e salva dopo ogni file.
- L’annullamento mantiene i trasferimenti già completati. Il ripristino dal Cestino non ricrea automaticamente le appartenenze agli album.
- Possibili aggiunte successive: distanze diverse di precaching avanti/indietro e cronologia delle cartelle aperte.

# Stato della prima versione — 7 ottobre 2026

## Consegna

- App compilata e firmata localmente: `dist/Photor.app`.
- Spiegazione della pipeline, dei componenti e delle fondamenta: [PIPELINE.md](PIPELINE.md).
- Avvio, comandi e ricompilazione: [README.md](../README.md).
- Tre moduli separati: Core, Decoders e Rendering; app macOS con interfaccia SwiftUI e finestra AppKit.

## Funzioni presenti

Apertura e trascinamento di una cartella, navigazione con frecce e pulsanti, contatore, pinch-to-zoom, pan, adattamento e 100%, precaching dinamico, conservazione opportunistica delle immagini già preparate, budget configurabile e riduzione della cache su segnalazione di pressione della memoria.

JPEG e RAF sono implementati. I RAW mostrano prima l’anteprima e vengono sviluppati in background tramite Core Image. Gli originali restano invariati.

## Verifiche effettivamente eseguite

| Verifica | Risultato |
|---|---|
| Build Swift in modalità release | Superata |
| Integrità della firma locale e Info.plist | Superata |
| Budget e durata delle prenotazioni di memoria | Superata |
| Priorità, limiti del catalogo e raggio RAW | Superata |
| Eliminazione delle immagini meno prioritarie | Superata |
| Catalogo, ordinamento naturale, EXIF, ridimensionamento e sRGB | Superata |
| Cambio cartella durante decodifiche attive, esclusione dei vecchi risultati e limite di due worker | Superata |
| JPEG e RAF reali: preview, piena risoluzione, pixel non vuoti e texture Metal | Superata |
| App confezionata: finestra, contatore, zoom 100%, ingrandimento e adattamento | Superata |
| App confezionata: ritorno sincrono alla foto in cache e 40 cambi rapidi | Superata |
| Completamento del disegno GPU nella finestra | Superata |

È stato anche ispezionato il risultato del renderer Metal esportato come immagine. La cattura bitmap ordinaria della vista AppKit non include il contenuto della superficie Metal; per questo il renderer viene controllato separatamente con la stessa pipeline grafica.

Ambiente verificato: Apple M5 Pro, macOS 26.6.2. Campioni: `DSCF0023.JPG` e `DSCF0023.RAF` della X-T50. Le verifiche dei gesti esercitano il codice di zoom e della viewport; non sostituiscono una prova manuale con le dita sul trackpad.

## Cosa manca per valutarla nell’uso quotidiano

1. **Cartella grande:** misurare latenza, percentuale di foto già pronte e memoria con centinaia di JPEG differenti. Due campioni non misurano la resa del precaching su 600 fotografie.
2. **Uso prolungato:** controllare memoria del processo e comportamento sotto reale pressione della RAM, anche insieme alle altre app abituali.
3. **Prova manuale:** valutare sensibilità del pinch e del pan sul tuo trackpad, e comportamento su eventuali monitor esterni.

## Funzioni aggiuntive non incluse

Aggiornamento automatico quando i file della cartella cambiano, esplorazione ricorsiva delle sottocartelle e raggruppamento JPEG+RAW dello stesso scatto. Attualmente puoi riaprire la cartella per rileggerla; JPEG e RAF vengono contati separatamente.

Queste sono estensioni possibili. La prima versione richiesta, con navigazione, zoom, contatore e precaching, è implementata e avviabile.

## Future possibili features
- dividere la selezione tra + e - di quante foto in avanti si vogliono caricare in memoria ()ex. vogliamo 50 foto indietro ma 200 avanti
- mettere 2/3 icone che appaiono nel menu della foto in modo per esempio da poter catalogare le foto secondo categorie standard ch decido, una di queste sarebbe sicuramente una stella per i preferiti e magari le altre 2 custom. Quello che succede è che il programma tiene uno stato persistente della lista relativa al path che stiamo usando, quindi quella cartella, di dove abbiamo scelto di mettere le foto. successivamente in un secondo momento futuro si può decidere di prendere quella lista guardarla, aggiungerere o togliere e quando si è soddisfatti con un tasto 'crea cartella', ciò che succede è che dal path della cartella, vengono create le 2/3 sotto cartelle tra cui preferiti e volendo le 2 custom (o comun que solo la cartella che si sta decidendo di creare nel path) e successivamente le foto selezionate vengono spostate da path a path/cartella (ex. io voglio mettere alcune foto come star, allora clicco l'icona della stella mentre scorro le foto su quelle che mi piacciono, successivamente in un secondo momento quel che faccio è andare a riaccedere al path che comunque ha memorizzato anche il programma e mostra in una interfaccia apposita la lista dei vari path che abbiamo usato nel tempo nei quali c'erano foto ex. fuji/luglio, fuji/agosto, .... e schiacciando quel tasto viene create nel path selezionato una sottocartella "star" e vengono semplicemente spostate le foto fa path a path/star)

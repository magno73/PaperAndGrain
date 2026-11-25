# Paper & Grain

Paper & Grain è un’app Mac per trasformare un album di viaggio in un fotolibro che alterna foto e racconti. Il primo libro di prova è Namibia. La prima build è per macOS 14 o successivo e usa SwiftUI, PhotoKit, Vision e Core Graphics.

## Compilare e aprire

Con Xcode selezionato come toolchain, dalla radice del repository:

```sh
./scripts/build-app.sh
open 'dist/0.10.0-redesign/Paper & Grain Redesign.app'
```

Lo script raccoglie eseguibile, risorse, traduzioni e configurazione di Foto in un bundle con firma locale. Il percorso include la versione. Sul branch `redesign/mac-ui` l’app si chiama «Paper & Grain Redesign» e tiene le bozze in una cartella propria. Se hai già un libro aperto, completa e salva il lavoro nella build corrente prima di aprire un altro bundle. Per la build ottimizzata usare `./scripts/build-app.sh release`. Il progetto SwiftPM si può aprire da Xcode per lavorare sui sorgenti. Usare il bundle per il collaudo di Foto.

Un agente può comporre, analizzare e modificare un libro dal terminale, poi esportare un PDF. La [guida della CLI](docs/cli.md) contiene i comandi e le specifiche JSON.

## Fare un primo libro

1. Apri **Scegli un album da Foto** e, al primo accesso, autorizza l’app nelle finestre di macOS. Scegli **Namibia**, seleziona le immagini, imposta il formato e premi **Impagina**. **Importa file** accetta immagini dal Finder. Il nuovo libro si apre sulla scelta del modello: **Applica** imposta carta, caratteri e margini, **Annulla** tiene lo stile di base. Il libro dimostrativo si apre senza accedere alla libreria.
2. A sinistra vedi le miniature delle doppie con tutte le foto nella loro posizione. Trascina una singola miniatura per riordinare la sua pagina. Il **+** inserisce una pagina nel punto indicato, anche tra due pagine affiancate. Una panoramica rimane un solo elemento. Seleziona una miniatura e premi **Canc** o **⌫** per eliminare la pagina. **⌘Z** la ripristina. Sopra la pagina puoi scegliere la vista singola o doppia e uno zoom da 25% a 200%.
3. Scrivi o incolla un racconto nell’ispettore. **Foto suggerite** mostra gli scatti ancora disponibili per la pagina che corrispondono al testo. Nella **Fototeca**, usa il menu di ordinamento per sfogliare gli scatti per **Data** (dalle prime giornate alle ultime), **Luogo**, **Argomento** o **Non usate prima**. La ricerca e il filtro per tema si combinano con l’ordinamento. Per i luoghi si usano i nomi nei metadati o le zone GPS, con **Senza luogo** in fondo. Rilascia immagini dal Finder o da Foto su **Trascina foto qui** per aggiungerle alla libreria del libro.
   Su un libro già analizzato usa **Aggiorna analisi** dal menu **…** della fototeca per aggiungere etichette con confidenza, rilevamenti, testo letto nell’immagine e dati visivi. Seleziona una foto e apri **Dettagli analisi** nella scheda **Foto** dell’ispettore.
4. **Salva progetto** chiede la posizione al primo salvataggio e aggiorna il pacchetto `.papergrain` già aperto nelle volte successive. **Salva con nome…** crea una copia. **Esporta PDF** apre il selettore di profilo con la verifica di prestampa. La lingua (sistema, italiano o inglese) si sceglie in **Paper & Grain › Impostazioni** (⌘,).

## La finestra

- A sinistra le **Pagine**: trascina il bordo per allargare il navigatore e ingrandire le miniature. Il **+** fra due pagine compare al passaggio del puntatore. Il menu contestuale inserisce, sposta o elimina una pagina. Dopo un clic su una miniatura, **←** e **→** passano alla pagina precedente o successiva, **↑** e **↓** alla doppia. **⌃⌘S** mostra o nasconde il pannello.
- In alto la barra di sistema: titolo e numero di pagine, **Inserisci**, **Stile** (il modello del libro), **Impagina** (il modello della pagina), **Pellicola**, **Esporta**, **Fototeca** e **Ispettore**. Un clic sul titolo apre **Libro e stampa**, **Modelli del libro**, i salvataggi e le esportazioni.
- In fondo la **Fototeca** (⌥⌘L): filtri **Tutte**, **Non usate**, **In pagina**, ordinamento, temi e ricerca. Trascina uno scatto sulla pagina o rilascia file dal Finder o da Foto nel cassetto. In una finestra stretta i filtri diventano un menu.
- A destra l’**Ispettore** (⌥⌘I). Le schede seguono la selezione: **Pagina** o **Copertina**, **Testo** con un titolo, un racconto o un box selezionato, **Foto** con una foto selezionata, **Pellicola** per il look del libro. La finestra non si stringe oltre lo spazio dei pannelli aperti.
- Sotto una foto selezionata compaiono **Ritaglia**, **Regola**, **Pellicola** e **Togli dalla pagina**. Gli stessi comandi sono nel menu **Foto**.
- Il tasto destro, o il clic con **⌃**, su una foto, un box o un testo apre il menu di quell’elemento: ritaglio e regolazioni, modifica del testo, **Porta in primo piano**, **Porta avanti**, **Porta indietro** e **Porta in fondo**. Gli stessi comandi sono nel menu **Disponi** (⇧⌘F, ⌥⇧⌘F, ⌥⇧⌘B, ⇧⌘B).
- Con la pagina intera a schermo, la rotella o lo scorrimento con due dita sfogliano il libro: in giù o a destra in avanti, in su o a sinistra indietro. Con lo zoom il canvas scorre normalmente. A canvas attivo e senza selezione, **←** e **→** girano pagina.
- **Vista** contiene pagina singola o doppia (⌘1, ⌘2), lo zoom (⌘+, ⌘−, ⌘0), la guida della piega e **Sfoglia il libro** (⌥⌘↩). In Sfoglia, le frecce cambiano doppia ed **Esc** chiude.
- La cornice dell’app segue la modalità chiara o scura del Mac. Le pagine mantengono i colori del modello.

## Montare le pagine

- Un clic seleziona l’elemento visibile più in alto. Clicca sulla carta libera o fuori dalla pagina per deselezionare, oppure usa **Esc** o **⇧⌘A**. Le frecce spostano l’oggetto selezionato di un punto. Tieni premuto **⇧** per spostarlo di dieci punti.
- Con il canvas attivo, premi **Canc** o **⌫** per rimuovere la foto o il box selezionato. **⌘Z** ripristina l’elemento. I pulsanti ai lati della barra mostrano o nascondono **Pagine** e **Ispettore**. Gli scatti in attesa di un riquadro si gestiscono nell’elenco **Foto nella pagina**.

- In **Foto**, le miniature mostrano l’intero scatto e un’icona indica se è verticale, orizzontale o quadrato. Il bollino indica la prima pagina in cui compare uno scatto. **C** e **R** indicano copertina e retro. Se la foto è usata più volte, passa il puntatore sulla miniatura per vedere tutte le posizioni. Fai doppio clic su uno scatto per inserirlo o toglierlo dalla pagina corrente. Trascinalo dal riquadro direttamente nel punto in cui vuoi posizionarlo. Sulla pagina puoi selezionarlo e premere **⌫** o **Canc** per rimuoverlo dalla composizione. Lo scatto resta nella libreria del libro. Le maniglie agli angoli permettono di ingrandirlo anche oltre il bordo. La parte oltre il taglio rimane fuori dalla pagina. Fai doppio clic sulla foto in pagina per modificarne il ritaglio e premi **Fine** per applicare.
- In **Pagina → Modello di pagina** scegli una composizione **Con margini** o **Al vivo**. È l’unico selettore del tipo di pagina: **Galleria automatica** dispone le foto da sola, gli altri modelli fissano le cornici, **Solo testo** e i modelli con testo sostituiscono le vecchie pagine di testo e miste. Scegli **Due pagine** e trascina una foto sulla doppia per riempirla. I modelli al vivo comprendono anche due foto affiancate o una sopra l’altra, tre colonne, una griglia di quattro e una foto grande sopra due più piccole. Scegliere un modello ridistribuisce le cornici. Testo, box, scatti e ritagli restano associati alla pagina. Gli scatti che eccedono la capienza del modello sono indicati nella lista della pagina e tornano visibili quando c’è posto.
- Per scambiare due foto della stessa pagina, trascina una foto all’interno dell’altra e rilascia quando vedi il bordo con le frecce. I ritagli seguono i rispettivi scatti. Tieni premuto **⌥** per sovrapporre liberamente le foto. **⌘Z** annulla lo scambio.
- **Inserisci → Box di testo** crea un riquadro indipendente. **Inserisci → Titolo di pagina** aggiunge un titolo anche su una pagina fotografica. Clicca un titolo, un racconto o un box e trascinalo per spostarlo. Usa le maniglie laterali per allargarlo e gli angoli per cambiarne anche l’altezza. Fai doppio clic per scrivere nella pagina. Titolo e racconto si adattano alla larghezza impostata. **Usa tutta la larghezza** elimina i margini interni di un box.
- Trascina lo sfondo del racconto o la maniglia **Sposta blocco** per muovere insieme titolo, testo e sfondo. Trascina direttamente il titolo o il testo per spostare solo quel riquadro.
- In **Tipografia**, usa **−** e **+** per cambiare la dimensione di un punto o digita il valore nel campo.
- Quando sposti una foto o un box, le guide colorate indicano l’aggancio a bordi e centri degli altri elementi nella pagina. Le guide compaiono anche trascinando una foto dalla scheda **Foto** o usando le maniglie della foto e del riquadro di ritaglio. Continua oltre la soglia o tieni premuto **⌥** mentre trascini per posizionare liberamente.
- **Copertina**, **Prima pagina** e **Retro copertina** si aprono dal navigatore. **Inserisci → Frontespizio** aggiunge una pagina iniziale con il titolo del libro. Su fronte e retro puoi trascinare una foto, spostarla, ridimensionarla con le maniglie e fare doppio clic per ritagliarla. Seleziona un testo per spostarne o allargarne il riquadro e aprire i controlli tipografici. Fai doppio clic per scrivere nel canvas. Se la faccia è vuota, usa **Aggiungi testo**.

## Modelli del libro

Da **Stile** nella barra, da **Pagina → Modello del libro** o da **File › Modelli del libro…** scegli fra dodici modelli in tre famiglie: **Classici** (Diario, Atlante, Galleria, Essenziale), **Studio** (Griglia svizzera, Quaderno berlinese, Intervallo giapponese) e **Fotolibro d’autore** (Monografia, Cartolina, Notturno, Kodachrome, Diario di bordo), ispirati ai fotolibri premiati. Il modello imposta carta, tipografia, ritmo della pagina e copertina. Nella stessa finestra, **Mostra numeri di pagina** controlla la numerazione stampata sulle pagine con margini. Puoi inserire un titolo dall’ispettore nelle pagine con testo. [Dettagli dei modelli](docs/templates.md).

## Formattare titoli e testi

Seleziona un titolo, un racconto o un box: l’ispettore apre la scheda **Testo**, come il pannello Formato di Keynote. **Carattere** sceglie famiglia e variante, la dimensione si cambia con **−**, **+** o digitando i punti, e il colore con i campioni del modello o il selettore di sistema. Seguono **Allineamento** e **Interlinea**. **Ripristina stile del modello** toglie le modifiche locali. **Disposizione** porta l’elemento in primo piano o in fondo. In **Libro e stampa → Tipografia del libro** imposti font, dimensione in punti e allineamento predefiniti per tutti i titoli e tutti i testi. Anche copertina e retro hanno controlli propri. Il selettore cerca fra i caratteri installati sul Mac, permette di scegliere famiglia e variante e mostra l’anteprima con il testo selezionato. Preferiti e recenti restano sul Mac. Il ripristino riporta il testo ai valori ereditati. Anteprima, miniature e PDF condividono lo stile del progetto.

## Pellicole e stampa

Seleziona una foto: la scheda **Foto** riunisce **Regola**, **Pellicola** della singola foto e **Analisi** in sezioni che si aprono e chiudono. La bacchetta **Migliora in automatico** analizza la foto sul Mac e propone valori modificabili di luce e colore. I controlli comprendono luce, colore e bilanciamento del bianco, bianco e nero, dettagli e nitidezza, riduzione del rumore, vignettatura, curve, livelli e colore selettivo. Il confronto mostra il file di partenza. Le modifiche seguono lo scatto in ogni pagina e nel PDF.

La scheda **Pellicola** applica un look a tutto il libro, la sezione **Pellicola** della scheda **Foto** a una sola foto, con intensità, grana e dimensione regolabili. **Originale** permette il confronto. Si possono importare LUT fotografiche 3D CUBE e HaldCLUT PNG. Il pacchetto conserva una copia dei file importati e ogni foto può ereditare il look del libro. Ogni scelta di look o trascinamento di un cursore forma una singola azione per **⌘Z**. Anche **Applica** in **Libro e stampa** o in **Modelli del libro** si annulla con una sola azione.

Il menu **Scegli LUT** mostra il nome della LUT attiva e contiene le 14 LUT sRGB di abpy. Da qui puoi anche importare una LUT personale. Le undici LUT in **Base a contrasto lineare** richiedono uno sviluppo con contrasto lineare. Le tre in **Da Provia** sono pensate per immagini già sviluppate con Provia. Il file che scegli viene copiato nel progetto. [Crediti e licenza delle LUT](Resources/FujifilmFilmLooks/CREDITS.md).

In **Libro e stampa** si possono cambiare formato (scegliendo fra 21 misure tipiche di fotolibro o una misura personalizzata), bleed, margine, risoluzione desiderata, tipo di PDF e lato della prima pagina. Imposta la copertina con foto di fronte e retro e la larghezza del dorso. **Esporta per la stampa** produce `Interior.pdf` e, se attivata, `Cover.pdf`. L’esportazione segnala foto sotto la risoluzione obiettivo e pagine di compensazione necessarie per i panorami. Usa le misure del prodotto scelto presso la tipografia.

Da **Esporta PDF** puoi scegliere **PDF da sfogliare**, **Stampa generica** o **Pixartprinting · 21 × 21 cm**. Il profilo Pixartprinting richiede un libro di quel formato con copertina e il dorso in millimetri dal preventivo. Produce un PDF unico in scala 1:1 con copertina rigida stesa e facciate interne singole da 216 × 216 mm, inclusi 3 mm di abbondanza per lato. La foliazione segue il libro e le eventuali pagine di compensazione. Il profilo del PDF è sRGB. I requisiti colore del prodotto si verificano nelle istruzioni del preventivo. [Pixartprinting · Fotolibri](https://www.pixartprinting.it/stampa-riviste-cataloghi-libri/fotolibri/)

## Foto e dati del progetto

L’app copia le immagini selezionate nel progetto. Foto può recuperare da iCloud gli originali selezionati quando servono. Vision esegue sul Mac l’analisi delle copie orientate, usando immagini ridotte fino a 640 pixel. Il pacchetto conserva le etichette e i temi. Il confronto col racconto usa etichette e parole in italiano e inglese. In caso di analisi incompleta, l’editor consente di riprovare.

Il libro nasce come bozza nell’area Application Support dell’utente. Il pacchetto che si salva esplicitamente contiene le immagini, l’analisi e il documento. Trattarlo come l’album originale quando lo si condivide. Le foto e gli appunti privati del viaggio Namibia si tengono fuori dal repository.

## Stato e sviluppo

L’impaginazione iniziale resta in ordine di scatto e in righe che rispettano le proporzioni. Il PDF di prova e il pacchetto di stampa condividono colore e composizione. La produzione va collaudata sul formato scelto presso la tipografia.

- [Architettura e formato del documento](docs/architecture.md)
- [Collaudi e stato delle funzionalità](docs/status.md)
- [Confronto del motore con Fotobuch](docs/layout-comparison.md)
- [Istruzioni per chi lavora al codice](AGENTS.md)

`swift test` verifica la riapertura dei documenti, il trasferimento delle LUT e la geometria dei PDF.

# Paper & Grain

Paper & Grain è un’app Mac per trasformare un album di viaggio in un fotolibro che alterna foto e racconti. Il primo libro di prova è Namibia. La prima build è per macOS 14 o successivo e usa SwiftUI, PhotoKit, Vision e Core Graphics.

## Compilare e aprire

Con Xcode selezionato come toolchain, dalla radice del repository:

```sh
./scripts/build-app.sh
open 'dist/0.9.1/Paper & Grain.app'
```

Lo script raccoglie eseguibile, risorse, traduzioni e configurazione di Foto in un bundle con firma locale. Il percorso include la versione. Se hai già un libro aperto, completa e salva il lavoro nella build corrente prima di aprire un altro bundle. Per la build ottimizzata usare `./scripts/build-app.sh release`. Il progetto SwiftPM si può aprire da Xcode per lavorare sui sorgenti. Usare il bundle per il collaudo di Foto.

Un agente può comporre, analizzare e modificare un libro dal terminale, poi esportare un PDF. La [guida della CLI](docs/cli.md) contiene i comandi e le specifiche JSON.

## Fare un primo libro

1. Apri **Scegli un album da Foto** e, al primo accesso, autorizza l’app nelle finestre di macOS. Scegli **Namibia**, seleziona le immagini, imposta il formato e premi **Impagina**. **Importa file** accetta immagini dal Finder. Il libro dimostrativo si apre senza accedere alla libreria.
2. A sinistra vedi le miniature delle doppie con tutte le foto nella loro posizione. Trascina una singola miniatura per riordinare la sua pagina. Una panoramica rimane un solo elemento. Sopra la pagina puoi scegliere la vista singola o doppia e uno zoom da 25% a 200%.
3. Scrivi o incolla un racconto nell’ispettore. **Foto suggerite** mostra gli scatti ancora disponibili per la pagina che corrispondono al testo. Nella scheda **Foto** puoi sfogliare gli scatti per tema. Rilascia immagini dal Finder o da Foto su **Trascina foto qui** per aggiungerle alla libreria del libro.
   Su un libro già analizzato usa **Aggiorna analisi** in **Foto** per aggiungere etichette con confidenza, rilevamenti, testo letto nell’immagine e dati visivi. Seleziona una foto e apri **Dettagli analisi**.
4. **Salva progetto** chiede la posizione al primo salvataggio e aggiorna il pacchetto `.papergrain` già aperto nelle volte successive. **Salva con nome…** crea una copia. **Esporta PDF** apre il selettore di profilo. Il globo sceglie lingua di sistema, italiano o inglese.

## Montare le pagine

- Un clic seleziona l’elemento visibile più in alto. Clicca sulla carta libera o fuori dalla pagina per deselezionare, oppure usa **Esc** o **⇧⌘A**. Le frecce spostano l’oggetto selezionato di un punto. Tieni premuto **⇧** per spostarlo di dieci punti.
- Premi **Canc** o **⌫** sulla foto in pagina o in copertina, oppure su un box di testo selezionato, per rimuoverlo. **⌘Z** ripristina l’elemento. Gli scatti in attesa di un riquadro si gestiscono nell’elenco **Foto nella pagina**.

- In **Foto**, fai doppio clic su uno scatto per inserirlo o toglierlo dalla pagina corrente. Trascinalo dal riquadro direttamente nel punto in cui vuoi posizionarlo. Sulla pagina puoi selezionarlo e premere **⌫** o **Canc** per rimuoverlo dalla composizione. Lo scatto resta nella libreria del libro. Le maniglie agli angoli permettono di ingrandirlo anche oltre il bordo. La parte oltre il taglio rimane fuori dalla pagina. Fai doppio clic sulla foto in pagina per modificarne il ritaglio e premi **Fine** per applicare.
- In **Pagina → Modello di pagina** scegli una composizione **Con margini** o **Al vivo**. I modelli al vivo comprendono due foto affiancate o una sopra l’altra, tre colonne, una griglia di quattro e una foto grande sopra due più piccole. Scegliere un modello ridistribuisce le cornici. Testo, box, scatti e ritagli restano associati alla pagina. Gli scatti che eccedono la capienza del modello sono indicati nella lista della pagina e tornano visibili quando c’è posto.
- Per scambiare due foto della stessa pagina, trascina una foto all’interno dell’altra e rilascia quando vedi il bordo con le frecce. I ritagli seguono i rispettivi scatti. Tieni premuto **⌥** per sovrapporre liberamente le foto. **⌘Z** annulla lo scambio.
- **Inserisci → Box di testo** crea un riquadro indipendente. **Inserisci → Titolo di pagina** aggiunge un titolo anche su una pagina fotografica. Clicca un titolo, un racconto o un box e trascinalo per spostarlo. Usa le maniglie laterali per allargarlo e gli angoli per cambiarne anche l’altezza. Fai doppio clic per scrivere nella pagina. Titolo e racconto si adattano alla larghezza impostata. **Usa tutta la larghezza** elimina i margini interni di un box.
- Trascina lo sfondo del racconto o la maniglia **Sposta blocco** per muovere insieme titolo, testo e sfondo. Trascina direttamente il titolo o il testo per spostare solo quel riquadro.
- In **Tipografia**, usa **−** e **+** per cambiare la dimensione di un punto o digita il valore nel campo.
- Quando sposti una foto o un box, le guide colorate indicano l’aggancio a bordi e centri degli altri elementi nella pagina. Le guide compaiono anche trascinando una foto dalla scheda **Foto** o usando le maniglie della foto e del riquadro di ritaglio. Continua oltre la soglia o tieni premuto **⌥** mentre trascini per posizionare liberamente.
- **Copertina**, **Prima pagina** e **Retro copertina** si aprono dal navigatore. **Inserisci → Frontespizio** aggiunge una pagina iniziale con il titolo del libro. Sulle facce della copertina puoi trascinare una foto o sceglierla dalla scheda **Foto**, spostare e ridimensionare titolo e testo del retro e aprire **Regola foto** o **Pellicola** dallo stesso pannello.

## Modelli del libro

Da **Libro e stampa → Modelli del libro** scegli **Diario**, **Atlante**, **Galleria** o **Essenziale**. Il modello imposta carta, tipografia, ritmo della pagina e copertina. Puoi inserire un titolo dall’ispettore nelle pagine con testo. [Dettagli dei modelli](docs/templates.md).

## Formattare titoli e testi

In **Libro e stampa → Tipografia del libro** imposti font, dimensione in punti e allineamento predefiniti per tutti i titoli e tutti i testi. In **Pagina → Tipografia** puoi cambiare questi valori per la singola pagina. Anche copertina, retro e box selezionati hanno controlli propri. Il selettore cerca fra i caratteri installati sul Mac, permette di scegliere famiglia e variante e mostra l’anteprima con il testo selezionato. Preferiti e recenti restano sul Mac. Il ripristino riporta il testo ai valori ereditati. Anteprima, miniature e PDF condividono lo stile del progetto.

## Pellicole e stampa

Seleziona una foto e apri **Foto → Regola**. La bacchetta **Migliora in automatico** analizza la foto sul Mac e propone valori modificabili di luce e colore. I controlli comprendono luce, colore e bilanciamento del bianco, bianco e nero, dettagli e nitidezza, riduzione del rumore, vignettatura, curve, livelli e colore selettivo. Il confronto mostra il file di partenza. Le modifiche seguono lo scatto in ogni pagina e nel PDF.

La scheda **Pellicola** applica un look al libro o alla foto selezionata, con intensità, grana e dimensione regolabili. **Originale** permette il confronto. Si possono importare LUT fotografiche 3D CUBE e HaldCLUT PNG. Il pacchetto conserva una copia dei file importati e ogni foto può ereditare il look del libro.

Il menu **LUT Fujifilm** contiene già le 14 LUT sRGB di abpy. Le undici LUT in **Base a contrasto lineare** richiedono uno sviluppo con contrasto lineare. Le tre in **Da Provia** sono pensate per immagini già sviluppate con Provia. Il file che scegli viene copiato nel progetto. [Crediti e licenza delle LUT](Resources/FujifilmFilmLooks/CREDITS.md).

In **Libro e stampa** si possono cambiare formato, bleed, margine, risoluzione desiderata, tipo di PDF e lato della prima pagina. Imposta la copertina con foto di fronte e retro e la larghezza del dorso. **Esporta per la stampa** produce `Interior.pdf` e, se attivata, `Cover.pdf`. L’esportazione segnala foto sotto la risoluzione obiettivo e pagine di compensazione necessarie per i panorami. Usa le misure del prodotto scelto presso la tipografia.

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

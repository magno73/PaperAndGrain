# Stato dello sviluppo

## 0.10.0-redesign · bordi della pagina magnetici · 25 novembre 2026

Spostando o ridimensionando, foto, box, testi e foto di copertina si agganciano ai bordi e al centro della pagina, con guida visibile. Il bordo ha una portata più ampia degli altri oggetti: 10,5 punti a schermo invece di 6 (`CanvasAlignment.edgeToleranceFactor`). Così una foto rilasciata a pochi punti dal taglio arriva esattamente al bordo, e il PDF la estende in abbondanza. Vale anche per il ritaglio, il trascinamento dalla fototeca e il blocco del racconto. **⌥** disattiva ogni aggancio.

**Verificato nell’app:**
- una foto spostata a circa 5 punti dal bordo sinistro si aggancia al bordo;
- ridimensionata dalla maniglia fino a 4 punti dal bordo destro, arriva al bordo.

`swift test` esegue 134 test, fra cui la portata del bordo pagina rispetto agli altri oggetti.

**Resta da provare:** l’aggancio al bordo esterno di una doppia.

## 0.10.0-redesign · sostituzioni, box, copertina, aiuto · 25 novembre 2026

- **Selezione nell’album di Foto.** `scaledToFill().clipped()` nasconde la parte in eccesso dell’immagine, ma SwiftUI la considera ancora per i clic. Una foto verticale prendeva i clic delle celle vicine finché lo scorrimento non cambiava l’ordine di disegno. Le miniature ora ricevono clic solo nel riquadro visibile; lo stesso vale per le anteprime dell’editor e le copertine dei recenti.
- **Sostituzione con proporzioni diverse** (`BookPage.replacePhoto`), senza ritagli nascosti:
  - proporzioni simili: stessa cornice;
  - galleria che segue le proporzioni: la pagina si ricompone;
  - modelli fissi, gallerie dei modelli Studio e Fotolibro, cornici manuali: la cornice si riduce alla foto intera, centrata, e le altre foto restano ferme;
  - al vivo: la foto riempie lo spazio.
  Negli ultimi due casi un avviso sul canvas spiega cosa è successo.
- **Copertina.** La tipografia è nella scheda **Testo**. I pulsanti Regola e Pellicola non ci sono più: la foto di copertina si seleziona e si regola nella scheda **Foto**.
- **Box di testo.** Sfondo nessuno, carta o colore e bordo da 0,5 a 12 pt, in tela, miniature e PDF (`PageTextBox.backgroundColor`, `hidesBackground`, `borderColor`, `borderWidth`, campi facoltativi).
- **Fototeca.** Le miniature hanno le proporzioni della foto.
- **Informazioni e Aiuto.** **Informazioni su Paper & Grain** riporta autore, licenza e repository. **Aiuto › Aiuto di Paper & Grain** (⌘?) apre una guida in cinque passi, in italiano e inglese.

**Verificato nell’app** su un libro sintetico con il modello Kodachrome:
- panorama su una foto verticale di un modello a due: cornice ridotta e avviso;
- foto verticale nella galleria Kodachrome: adattata, non ritagliata;
- box con sfondo colorato e bordo da 2 pt;
- scheda **Testo** del titolo di copertina e pannello **Copertina** senza i vecchi pulsanti;
- miniature proporzionate;
- Informazioni e Aiuto.

`swift test` esegue 131 test.

**Resta da provare:**
- la selezione nell’album di Foto, con un album reale scelto dall’utente;
- bordo e sfondo dei box nel PDF di stampa;
- sostituzione su una doppia.

## 0.10.0-redesign · rilascio delle foto · 25 novembre 2026

- **Bordo che restava dopo un clic sulla carta.** Era l’anello di focus di macOS sull’oggetto cliccato, non la selezione. Ora è disattivato e la selezione la disegna solo l’app.
- **Foto della fototeca su una foto della pagina.** La sostituisce con la stessa cornice e nello stesso spazio. Anche nella galleria automatica il resto della pagina non si sposta.
- **Foto in uno spazio vuoto.** Riempie quello spazio preciso. Su una pagina automatica vuota entra nella composizione.
- Durante il trascinamento compare l’anteprima: bordo con icona sulla foto da sostituire, contorno tratteggiato sullo spazio da riempire.

**Verificato nell’app** su un libro sintetico, con trascinamenti reali dalla fototeca:
- clic sulla carta dopo una foto;
- sostituzione in un modello a quattro;
- riempimento dello spazio in basso a destra;
- sostituzione nella galleria automatica con le cornici invariate;
- scambio fra due foto della stessa pagina.

`swift test` esegue 127 test.

**Resta da provare:**
- sostituzione su una pagina al vivo;
- sostituzione su una doppia;
- rilascio con ⌥ sopra una foto.

## 0.10.0-redesign · velocità dell’ispettore e pellicola · 25 novembre 2026

**Selezione lenta di una foto.** Ho campionato il thread principale con `sample` su un libro sintetico di 50 pagine e 150 foto da 12 MP. Passando da una foto all’altra lavorava circa 2,4 s su 5. Metà del tempo era AppKit che ricostruiva le tacche dei cursori (`NSSliderTickMarks _rebuildTickMarkRectCache`): `Slider(step: 0.01)` crea circa 200 tacche per cursore. Il resto era layout del pannello aperto e ricalcolo del navigatore. Correzioni:
- cursori senza `step:`, con arrotondamento nel setter;
- sezioni di **Regola** chiuse all’apertura;
- navigatore ridisegnato solo quando cambia ciò che mostra.

Dopo le correzioni, lo stesso passaggio occupa il thread principale per circa 0,1 s.

**Pellicola.** Con una foto selezionata, la sezione **Pellicola** della scheda **Foto** cambia solo quella foto. **Cambia in tutto il libro**, che parte spenta a ogni selezione, cambia il look del libro e riporta la foto a seguirlo. La scheda **Pellicola** compare solo senza selezione e si chiama **Look di tutto il libro**. Indica le foto con un look proprio e offre **Uniforma**.

**Verificato nell’app** sul libro sintetico:
- tempi di selezione misurati con `sample`;
- Monocromatico su una sola foto;
- con la casella spuntata, Documentario su tutto il libro: la foto torna al look del libro;
- scheda Pellicola senza selezione.

`swift test` esegue 123 test.

**Resta da provare:**
- la selezione su un Mac meno recente;
- **Uniforma** con molte foto dal look proprio;
- l’import di una LUT con la casella spuntata.

## 0.10.0-redesign · editor dopo il primo collaudo · 25 novembre 2026

Correzioni chieste dopo il primo uso del fork:
- **Navigazione:** nel navigatore **←** e **→** cambiano pagina e **↑** e **↓** cambiano doppia. Con la pagina intera a schermo, la rotella o le due dita sfogliano il libro una doppia per gesto. A canvas attivo e senza selezione, **←** e **→** girano pagina.
- **Livelli:** il tasto destro su foto, box e testi apre un menu costruito sull’oggetto sotto il puntatore, con **Porta in primo piano**, **Porta avanti**, **Porta indietro** e **Porta in fondo**. Gli stessi comandi sono nel nuovo menu **Disponi**. L’ordine è salvato in `BookPage.layerOrder` e rispettato da canvas, miniature, clic e PDF.
- **Modelli:** un libro nuovo si apre sulla scelta del modello. Il modello si cambia anche da **Stile** nella barra e da **Pagina → Modello del libro**. Il pulsante del modello di pagina si chiama ora **Impagina**.
- **Finestra e libreria:** la finestra non si stringe oltre i pannelli aperti, e in poco spazio la Fototeca passa a controlli compatti. Le schede dei libri recenti restano quadrate anche con copertine verticali.
- **Ispettore:** la scheda **Foto** riunisce **Regola**, **Pellicola** della foto e **Analisi**, e la scheda **Pellicola** resta per il look del libro. La nuova scheda **Testo** contiene carattere, dimensione, colore, allineamento, interlinea e disposizione. Nel pannello **Pagina** resta un solo selettore del tipo di pagina, **Modello di pagina**.
- **Regola che spariva:** un clic sulla barra mobile sotto la foto arrivava anche al canvas come clic sulla carta e toglieva la selezione. I controlli mobili ora sono esclusi dai clic del canvas.
- **Foto lente:** fino a quattro anteprime in parallelo, risoluzione adatta alla cornice e miniatura del navigatore mostrata subito.

**Verificato** con il libro dimostrativo nell’app:
- frecce nel navigatore dalla copertina al retro;
- rotella sul canvas avanti e indietro;
- menu del tasto destro su una foto e **Annulla** dopo **Togli dalla pagina**;
- **In fondo** e corpo 17 pt centrato su un box, con lo stesso ordine nel PDF esportato dalla CLI;
- clic reale su **Regola** nella barra mobile: la selezione resta e la sezione si apre;
- scheda **Testo** aperta automaticamente da un box nuovo;
- finestra a 1400 punti senza ispettore tagliato, con la Fototeca compatta;
- griglia dei recenti con una copertina verticale;
- modello chiesto alla creazione di un libro da file.

`swift test` esegue 122 test, fra cui ordine dei livelli, compatibilità dei progetti senza `layerOrder`, gesti di scorrimento e colore e interlinea nel testo.

**Resta da provare:**
- la velocità delle anteprime su un libro grande come Namibia;
- il menu del tasto destro su un box e su un racconto;
- il colore personalizzato del testo nel PDF di stampa;
- lo scorrimento con un mouse a rotella classica.

## 0.10.0-redesign · modelli · 25 novembre 2026

`EditorView` è diviso in dodici estensioni per area. La vecchia griglia verticale della libreria, non più usata, è stata rimossa.

Ci sono cinque modelli nuovi nella famiglia **Fotolibro d’autore**: Monografia, Cartolina, Notturno, Kodachrome e Diario di bordo. Ogni modello ha una scala per il titolo di copertina e il dorso porta il titolo dai 5 mm in su. Con tre foto la Griglia svizzera non lascia più celle vuote. Il selettore dei modelli è diviso per famiglie su tre colonne.

**Verificato:**
- PDF di prova e di stampa per tutti i dodici modelli con un libro sintetico di dieci pagine;
- `swift test` con 113 test, fra cui le gallerie dei nuovi modelli senza sovrapposizioni e il titolo sul dorso;
- il selettore nell’app con il libro dimostrativo: tre famiglie su tre colonne, dodici anteprime, selezione con segno di spunta, **Annulla** senza modifiche. Un libro senza modello apre il selettore senza scelta attiva.

**Resta da provare:**
- la stampa reale di un dorso;
- la licenza di incorporazione dei caratteri di sistema nei PDF venduti.

## 0.10.0-redesign · 25 novembre 2026 · branch `redesign/mac-ui`

Nuova struttura della finestra secondo le linee guida di macOS 26 e 27. La barra degli strumenti è quella di sistema, con titolo, sottotitolo e menu del titolo (**Libro e stampa**, **Modelli del libro**, salvataggi ed esportazioni). La testata personalizzata non c’è più. L’ispettore è un `.inspector` nativo e le sue schede seguono la selezione: **Pagina** o **Copertina**, poi **Foto** e **Regola** quando una foto è selezionata, e infine **Pellicola**. La libreria delle foto diventa la **Fototeca**, un cassetto in fondo al canvas con i filtri **Tutte**, **Non usate** e **In pagina**, l’ordinamento, la ricerca e la zona per il trascinamento. Il navigatore è ridimensionabile e le miniature crescono con la sua larghezza. Il **+** fra le pagine compare al passaggio del puntatore. Su macOS 26 e successivi navigatore, fototeca e controlli del canvas usano Liquid Glass. Sui sistemi precedenti usano i materiali.

I nuovi menu **Inserisci**, **Pagina** e **Foto** e le voci aggiunte in **Vista** e **File** espongono tutte le azioni della barra e del canvas con le scorciatoie. **Apri recente** e la finestra di benvenuto mostrano i libri recenti con la copertina. Sotto la selezione compare un HUD con **Ritaglia**, **Regola**, **Pellicola** e **Togli dalla pagina**. Navigatore e canvas hanno un menu contestuale. **Sfoglia il libro** (⌥⌘↩) mostra le doppie a tutta finestra. La lingua si sceglie in **Impostazioni** (⌘,). I colori stanno in `Theme.swift` e seguono la modalità chiara o scura e il contrasto aumentato. Le pagine conservano i colori del modello. **Esporta PDF** mostra la verifica di prestampa prima di scegliere la destinazione. Il formato del libro offre 21 misure predefinite di fotolibro, quadrate, orizzontali e verticali, oltre a quella personalizzata.

Il navigatore resta nella stessa gerarchia del canvas. `NavigationSplitView` ospiterebbe le colonne in viste separate e interromperebbe trascinamenti e riferimenti di coordinate fra pagine, canvas e fototeca.

**Verificato sulla build `dist/0.10.0-redesign/`** con il libro dimostrativo:
- benvenuto, menu Inserisci › Pagina, trascinamento dalla fototeca alla pagina, riordino nel navigatore e Annulla dal menu Modifica;
- selettore dei modelli dalla barra, HUD, schede contestuali e Sfoglia;
- verifica di prestampa con un avviso reale di risoluzione e formati predefiniti in Libro e stampa;
- modalità scura, provata con un aggancio di debug poi rimosso;
- `swift test` con 111 test superati.

**Resta da provare:**
- un libro grande come Namibia, con prestazioni del cassetto e navigatore largo;
- ritaglio e testo in linea con il nuovo HUD;
- VoiceOver;
- l’aspetto su macOS 14 e 15.

La build usa un identificativo e una cartella di bozze propri, quindi non apre i libri della 0.9.x.

## 0.9.7 · 25 novembre 2026

**Canc** e **⌫** eliminano la pagina selezionata nel navigatore. **⌘Z** la ripristina. Il comando segue la selezione attiva, con copertine e campi di testo esclusi dall’eliminazione di pagine. La prova automatica verifica i due tasti e il controllo della pagina selezionata. La build risiede in `dist/0.9.7/`.

## 0.9.6 · 25 novembre 2026

Le miniature della libreria mostrano l’orientamento e conservano l’inquadratura originale. Il navigatore offre un **+** fra le pagine e mantiene il riordino per trascinamento nelle stesse posizioni. **Due pagine** è disponibile nel selettore dei modelli. Quando si trascina uno scatto da Foto sulla doppia, la cornice occupa entrambe le facciate. Le prove automatiche coprono l’inserimento ai confini della doppia e la sostituzione di una cornice piccola con una foto a tutta doppia. La build risiede in `dist/0.9.6/`.

## 0.9.5 · 24 novembre 2026

**Foto → Libreria** raggruppa per data, luogo, argomento o utilizzo. L’ordine predefinito segue la data di scatto. I luoghi dei file già importati vengono letti in sottofondo. Le foto senza i metadati richiesti restano consultabili in un gruppo in fondo. I test coprono ordinamento cronologico, zone GPS, metadati di immagini sintetiche e aggiornamento dei gruppi. La build risiede in `dist/0.9.5/`.

## 0.9.4 · 24 novembre 2026

**Modelli del libro** consente di mostrare o nascondere i numeri sulle pagine con margini. Anteprima, editor e PDF leggono la stessa impostazione. I progetti precedenti ereditano il valore del modello finché viene scelta un’impostazione esplicita. Il test verifica salvataggio, annullamento e testo effettivo nel PDF. La build risiede in `dist/0.9.4/`.

## 0.9.3 · 24 novembre 2026

La libreria mostra la pagina o la faccia della copertina in cui compare lo scatto. Una doppia pagina usa entrambi i numeri. Il bollino conta gli altri utilizzi e il tooltip li elenca. Il menu LUT mostra il nome del file importato o del profilo Fujifilm attivo anche quando è chiuso.

La prova automatica copre scatti fuori dalla composizione, doppi utilizzi, fronte, retro e aggiornamento della numerazione al riordino. La build risiede in `dist/0.9.3/`.

## 0.9.2 · 24 novembre 2026

Le scorciatoie degli oggetti seguono il focus del canvas. Le anteprime delle miniature restano riutilizzabili quando cambia solo la selezione. Pagine e Ispettore si possono nascondere indipendentemente. I cursori di Pellicola aggiornano un’anteprima ridotta su una coda dedicata e registrano una sola operazione annullabile al rilascio. È possibile annullare anche l’applicazione di Libro e stampa e del modello del libro. L’autosalvataggio codifica il manifest fuori dal thread dell’interfaccia.

Fronte e retro offrono selezione, trascinamento, ridimensionamento e ritaglio delle foto nel canvas. La selezione del testo apre i controlli tipografici. Miniature ed esportazione riprendono le cornici salvate. Le prove automatiche verificano geometria, salvataggio, annullamento delle impostazioni, code delle anteprime e resa nei PDF generico e Pixart. Resta da misurare nella finestra il tempo fra clic e comparsa della selezione su Namibia. La build risiede in `dist/0.9.2/`.

## 0.9.1 · 24 novembre 2026

La ricerca italiana riconosce le etichette Vision `sand dune` e `desert`. Il collaudo di Namibia ha analizzato 184 foto in circa 15 secondi e ha rilevato testo in 12 immagini. Le anteprime degli originali JPEG sono state verificate sul binario firmato fuori dal sandbox di collaudo. Resta da completare il collaudo dei permessi Apple Foto per l’invocazione da terminale. La build risiede in `dist/0.9.1/`.

## 0.9.0 · 24 novembre 2026

La CLI importa file o foto selezionate da album, aggiorna l’analisi, cerca e confronta le immagini, ritocca colore e pellicola, applica patch ai progetti ed esporta i profili PDF dell’app. Le modifiche CLI producono varianti riapribili. L’analisi di revisione 2 aggiunge classificazioni con confidenza, rilevamenti, testo riconosciuto e misure visive. L’editor spiega l’abbinamento di una foto al racconto e può aggiornare le analisi precedenti. [Guida della CLI](cli.md)

Verificati con immagini sintetiche analisi multilingue, OCR, modifiche, regolazioni, esportazione e rilettura dei pacchetti. Restano il collaudo dei permessi Apple Foto via terminale e una valutazione della qualità dei suggerimenti su Namibia. La build risiede in `dist/0.9.0/`.

## 0.8.1 · 24 novembre 2026

I tre modelli editoriali usano gallerie e riquadri **Testo sulla foto** distinti. I titoli hanno corpi più contenuti e si adattano alla larghezza quando possono stare su una riga con un corpo leggibile. Foto, titolo e riquadro condividono la posizione tra selettore dei modelli, editor, miniature ed esportazione. Verificate copertine, testo sulla foto e gallerie su esempi sintetici. La build risiede in `dist/0.8.1/`.

## 0.8.0 · 24 novembre 2026

Il canvas usa la geometria di disegno per selezionare l’elemento in primo piano. Il clic sul vuoto e i comandi da tastiera deselezionano. Le frecce spostano gli oggetti, Canc rimuove le foto e i box selezionati e Tipografia offre i comandi − e +. Il pannello Pagina prepara la numerazione delle destinazioni in un passaggio e carica le righe foto man mano. Il pannello Foto riusa i risultati dei filtri. I tre nuovi [modelli editoriali](templates.md) sono Griglia svizzera, Quaderno berlinese e Intervallo giapponese. La [CLI](cli.md) crea libri modificabili da specifiche JSON.

Verificati la geometria della selezione, le scorciatoie, i nuovi modelli su tre formati, copertine e pagine sintetiche esportate e la creazione di un pacchetto CLI con immagini locali. Restano il collaudo del puntatore nella finestra e la misura della risposta dei pannelli sul libro Namibia. La build risiede in `dist/0.8.0/`.

## 0.7.1 · 23 novembre 2026

La maniglia del racconto e il suo sfondo spostano insieme titolo, testo e sfondo. Il trascinamento diretto di titolo o testo agisce sul singolo riquadro. Il pannello **Foto** accetta immagini trascinate nella libreria del libro. I test verificano persistenza e spostamento dei riquadri, importazione di immagini e precedenza del file originale sulla miniatura. Resta da provare il rilascio dal Finder e da Foto nella finestra dell’app. La build risiede in `dist/0.7.1/`.

## 0.7.0 · 23 novembre 2026

Titolo, racconto, box e testi di copertina si spostano e si ridimensionano direttamente sulla pagina. Il selettore dei font offre famiglie, varianti, anteprima, preferiti e recenti. **Salva progetto** aggiorna il pacchetto già nominato e **Salva con nome** ne crea una copia. **Esporta PDF** aggiunge il profilo Pixartprinting 21 × 21 cm con copertina rigida e dorso da preventivo. I test verificano persistenza, larghezza delle cornici, scrittura del manifest, misure del PDF e paginazione con dorso variabile. Restano il collaudo dei gesti nella finestra e la verifica del file con il preventivo di stampa. La build risiede in `dist/0.7.0/`.

## 0.6.0 · 23 novembre 2026

Il selettore pagina raggruppa i modelli al vivo e aggiunge due foto affiancate, due in verticale, tre colonne, una griglia di quattro e una foto grande sopra due. In **Tipografia** si scelgono font, corpo e allineamento per titoli, racconti, copertina e box. Il libro può impostare valori predefiniti e gli oggetti possono modificarli singolarmente. I test coprono lettura dei progetti precedenti, ereditarietà, posizione del testo nel PDF, abbondanza e giunzioni delle foto. Resta il collaudo interattivo dei nuovi controlli. La build risiede in `dist/0.6.0/`.

## 0.5.3 · 23 novembre 2026

Due foto della stessa pagina si scambiano trascinando una foto all’interno dell’altra. Il bersaglio è evidenziato durante il trascinamento e **⌥** consente la sovrapposizione libera. Il cambio scheda dell’ispettore e le coordinate delle miniature in libreria aggiornano il pannello. I campioni Pellicola possono apparire mentre la coda delle miniature è impegnata. Verificati scambio di cornici, ritagli, persistenza, coordinate e indipendenza delle code. Restano da verificare il gesto nella finestra e i tempi di apertura dei pannelli sul progetto Namibia. La build risiede in `dist/0.5.3/`.

## 0.5.2 · 23 novembre 2026

La selezione foto parte al rilascio del clic e mantiene il pannello aperto. L’ispettore **Pagina** offre undici modelli per la singola pagina. **Regola foto** e **Pellicola** si aprono dal fronte e dal retro della copertina. Le prove automatiche coprono classificazione del clic, selezione per posizione con zoom, compatibilità dei modelli e resa della sovrapposizione testo e foto nel PDF. Resta da misurare la risposta al clic nella finestra con Namibia. La build risiede in `dist/0.5.2/`.

## 0.5.1 · 23 novembre 2026

Backspace e Canc agiscono sulla foto selezionata nel canvas. Il clic singolo seleziona subito e il doppio clic continua ad aprire il ritaglio o il box. Le maniglie agganciano le foto e i riquadri di ritaglio agli altri elementi. Le miniature e il canvas hanno code e cache separate. Lo spostamento dei cursori usa un’anteprima leggera. Le prove automatiche verificano scorciatoie, geometria dell’aggancio, cancellazione e condivisione delle richieste di anteprima. Resta da provare la reattività della finestra con un libro grande. La build risiede in `dist/0.5.1/`.

## 0.5 · 23 novembre 2026

Le miniature riproducono la composizione effettiva, affiancano le pagine e permettono il riordino di una pagina per volta. Canc rimuove dalla pagina la foto selezionata. Le cornici foto possono uscire dal taglio. Il doppio clic nei box apre la scrittura sulla pagina. **Foto → Regola** contiene la bacchetta automatica e le regolazioni condivise tra editor e stampa. Verificati geometria, persistenza dei progetti e resa delle regolazioni nei PDF con immagini sintetiche. Resta il collaudo delle interazioni native nella finestra aperta. La build risiede in `dist/0.5.0/`.

## 0.4.1 · 23 novembre 2026

L’editor aggancia foto e box ai bordi e ai centri degli altri elementi sulla stessa pagina. Le guide seguono il trascinamento e l’aggancio si rilascia continuando il movimento o tenendo premuto **⌥**. Il menu **LUT Fujifilm** include 14 CUBE sRGB verificati. Le prove automatiche coprono la soglia di rilascio, i vincoli della pagina, il caricamento delle LUT e la portabilità del progetto. Resta il collaudo visivo dei gesti nel libro aperto. La build risiede in `dist/0.4.1/`.

## 0.4 · 23 novembre 2026

Disponibili riordino delle pagine tramite trascinamento, zoom del canvas, doppio clic sulle foto della libreria, ridimensionamento e ritaglio sulla pagina, box di testo mobili, frontespizio e modifica di copertina e retro. I pannelli file sono schede asincrone e gli errori operativi appaiono nella finestra. Il collaudo dimostrativo ha verificato doppio clic, rilascio di una foto, riordino e spostamento del box. Le prove automatiche coprono compatibilità, geometria, posizione di testo e foto nel PDF, abbondanza e retro. Resta da provare l’interazione completa del nuovo ritaglio e il passaggio tra altre app con il Dock. La build risiede in `dist/0.4.0/`.

## 0.3 · 23 novembre 2026

Disponibili quattro [modelli editoriali](templates.md) con anteprime di selezione e titoli di pagina. Verificate la persistenza dei modelli, quattro doppie pagine e quattro copertine su immagini dimostrative. La build risiede in `dist/0.3.0/`. Per decidere il modello di Namibia, resta il collaudo sugli scatti scelti dall’album.

## 0.2 · 23 novembre 2026

| Area | Disponibile | Verifica |
|---|---|---|
| Impaginazione | Motore interno a righe, cambio formato, spostamento e copia tra pagine, testo sotto o a fianco | Confronto con un motore esterno su 36 immagini dimostrative e due formati; resta il motore interno. |
| Pellicole | Tre look nativi, grana, confronto con originale, look globale e per foto, import CUBE 3D/HaldCLUT PNG | Verificate LUT identità, tabella 13³, dominio CUBE, rifiuto di file troncato, grana ripetibile, riapertura dopo il trasferimento del pacchetto e conversione JPEG/HEIC Display P3 SDR in sRGB. |
| Stampa | Margine, abbondanza, PPI, prima pagina sinistra o destra, interni a pagine singole o doppie, copertina separata, sRGB | Verificati i box PDF, la continuità ai bordi interni del panorama e la paginazione con compensazione. |
| Progetto | Compatibilità con la 0.1, bundle nuovo in `dist/0.2.0/` | Ricaricata una bozza senza i nuovi campi e verificati i valori predefiniti. |

Il collaudo di composizione si è svolto su copie dimostrative. Restano il confronto visivo delle pagine di Namibia, una prova dedicata con una foto HEIC HDR e la verifica presso la tipografia scelta.

## 0.1 · 23 novembre 2026

| Area | Disponibile nella build | Verifica |
|---|---|---|
| Progetto | Pacchetto locale, salvataggio, riapertura e ripresa dell’ultimo libro | Verificata la scrittura e rilettura di un documento con testo, analisi e ritaglio. |
| Import | Picker di album Foto, scelta del formato, copia da Foto o Finder, esempio incluso | Import e analisi dell’esempio eseguiti nell’app. Resta il collaudo PhotoKit sull’album Namibia. |
| Editor | Italiano e inglese, navigatore, galleria, testo, pagina mista, al vivo e panoramica | Usati l’editor nativo, una doppia pagina e una pagina con testo e foto nell’app avviata. |
| Vision | Classificazione sul Mac, filtro tematico e suggerimenti dal testo | La foto dimostrativa è stata classificata come acqua, persone e all’aperto. Il brano «Siamo corsi fino al mare» l’ha suggerita nell’editor e l’autore può aggiungerla alla pagina. Il collaudo ha verificato anche match in inglese e un caso senza match. |
| PDF | Prova con testo vettoriale, una pagina per foglio e ritaglio coerente sul panorama | Verificate quattro pagine in un PDF indipendente. Un testo in eccedenza ha preservato il PDF già esistente. |
| Pellicole e stampa | Specifica e catalogo di riferimenti | Restano da implementare import LUT, grana, profili colore, controlli tipografici e profili di stampa. |

## Prossimo collaudo · Namibia

Aprire l’app, scegliere l’album Namibia con il permesso di macOS e importare una selezione che includa deserto, spostamenti, fauna e persone. Usare un box breve e una pagina di diario. Confrontare i suggerimenti con la selezione dell’autore e registrare almeno un match utile e gli eventuali scatti mancati. Verificare anche una foto modificata in Foto o disponibile solo in iCloud. Comporre una foto a tutta pagina e una a doppia pagina, quindi esportare la prova.

## Prima copia stampata

Scegliere formato, carta e rilegatura con la tipografia. Inserire le misure effettive in Libro e stampa, aprire i PDF a risoluzione reale e validare dorso, grana e dettaglio sui volti con un provino.

Il template Pixartprinting per il fotolibro da 21 × 21 cm usa interni singoli con abbondanza di 3 mm e una copertina stesa come prima pagina del PDF. Pixartprinting consiglia un PDF unico e accetta anche la consegna di copertina e interni separati. Per un export dedicato occorre usare la geometria della copertina del preventivo, con abbondanza e pieghe distinte da quelle degli interni, e lasciare variabile la foliazione. Il foglio di istruzioni del preventivo specifica i requisiti di colore e risoluzione. [Pixartprinting · Fotolibri](https://www.pixartprinting.it/stampa-riviste-cataloghi-libri/fotolibri/), [Assistenza · Come creare la copertina](https://support.pixartprinting.com/hc/it/articles/27577189469586-Come-creare-correttamente-la-copertina-di-un-libro)

# Stato dello sviluppo

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
| Impaginazione | Motore interno a righe, cambio formato, spostamento e copia tra pagine, testo sotto o a fianco | [Confronto con Fotobuch](layout-comparison.md) su 36 immagini dimostrative e due formati. |
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

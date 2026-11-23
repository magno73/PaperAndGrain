# Stato dello sviluppo

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

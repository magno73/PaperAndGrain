# Architettura

## Flusso

`AlbumPicker` seleziona foto e formato. `PhotoLibrary` chiede a PhotoKit la versione corrente delle immagini. L’import esplicito dal Finder passa per `LocalImages`. `Workspace` salva ogni risorsa in locale e crea il documento. Avvia l’analisi in serie dopo che l’editor è disponibile.

`EditorView` modifica il documento con binding SwiftUI. Un cambio nella foto o nel testo aggiorna la vista. Il salvataggio del manifest è ritardato di poco per evitare scritture ad ogni carattere. `BookPDF` lavora con una copia del documento per mantenere coerente ogni esportazione.

## Pacchetto di libro

Un progetto `.papergrain` ha `manifest.json` e una cartella `assets/` e, se necessario, `looks/`. I nuovi campi della 0.2 sono facoltativi nello schema v1.

| Dato | Responsabilità |
|---|---|
| Libro | ID, titolo, formato in mm, ordine delle pagine e versione dello schema |
| Foto | ID, nome, data di scatto, dimensioni orientate, filename locale e analisi facoltativa |
| Pagina | ID, tipo di composizione, foto nell’ordine di disposizione, racconto, posizione del testo e inquadratura facoltativa |
| Analisi | Lista di etichette Vision, chiavi stabili dei temi e revisione |
| Pellicola | Profilo del libro, eccezioni per foto e riferimento alla LUT inclusa nel progetto |
| Stampa | Abbondanza, margine, PPI, ordine delle facciate e copertina facoltativa |

Il manifest si sostituisce atomicamente. Il salvataggio esplicito copia il pacchetto in un percorso scelto dall’utente. Le risorse si risolvono sotto `assets/`. L’app conserva una bozza locale e riapre l’ultimo progetto idoneo quando parte. Cambi che aggiungono dati facoltativi devono poter decodificare i progetti salvati senza quei campi.

## Analisi e associazione dei racconti

`PhotoAnalyzer` usa ImageIO per normalizzare l’orientamento e Vision per classificare la scena. Dopo il filtro di confidenza, conserva le etichette più pertinenti. Associa quelle etichette a temi stabili come `desert`, `wildlife`, `water` e `people`. Le traduzioni dei temi servono all’interfaccia. Il matching usa etichette inglesi e sinonimi comuni in italiano e inglese, con punteggi positivi per le parole o espressioni riscontrate. Il tema descrive ciò che il modello riconosce e va trattato come una proposta. La classificazione corrente non stabilisce dove è stata scattata la foto o chi vi compare.

Le foto arrivate da PhotoKit possono provenire da iCloud. La copia richiede la versione corrente, incluse le modifiche visibili in Foto. La classificazione lavora sulla copia locale e memorizza l’analisi nel documento. Al cambio libro si interrompe la sequenza in corso.

## Geometria e PDF

Le dimensioni del libro sono in millimetri. La geometria della galleria passa per `BookLayoutGeometry` e conserva proporzioni, ordine e interspazi. La prima bozza raggruppa per giorno di scatto. Il [confronto con Fotobuch](layout-comparison.md) documenta la decisione di tenere il layout interno nella 0.2.

Per una foto al vivo, `framing` va da 0 a 1 sull’asse che viene tagliato quando la foto riempie la pagina. Un valore assente equivale a 0,5. La doppia pagina usa lo stesso rettangolo immagine per entrambi i lati. Il PDF disegna quel rettangolo attraverso due finestre di ritaglio e omette le guide. Core Text mantiene il testo selezionabile. Una foto mancante o un testo che eccede lo spazio interrompono l’export prima della sostituzione del file esistente.

L’esportazione di stampa usa TrimBox e BleedBox espliciti e incorpora sRGB come output intent. I fogli avviati a destra e i panorami possono richiedere pagine bianche di compensazione. La stampa produce interni e copertina in file separati. Abbondanza e dorso vanno impostati con le specifiche del prodotto scelto.

## Pellicole

`FilmRenderer` legge l’immagine orientata con ImageIO, la normalizza in sRGB con ColorSync e applica il look o il CUBE 3D/HaldCLUT PNG. L’intensità miscela la resa del look con la scena, la grana aggiunge una variazione ripetibile alla luminanza. Il riquadro originale dell’editor è una modalità temporanea di visione. Il documento salva il look del libro e le eccezioni per foto. La cache di anteprima è limitata e usa immagine, dettaglio del look e risoluzione come chiave. Il PDF rilegge la copia alla risoluzione utile per il formato.

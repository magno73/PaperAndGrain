# Modificare un progetto dal terminale

Il comando lavora su una copia del pacchetto e pubblica la variante solo dopo averla riletta. Ogni variante ha un nuovo UUID libro. La copia contiene gli originali delle immagini, le LUT e gli altri file del progetto. Il percorso di destinazione deve essere nuovo, con estensione `.papergrain`, in una cartella esistente esterna al progetto sorgente.

```sh
PaperAndGrain cli inspect originale.papergrain > manifest.json
PaperAndGrain cli patch originale.papergrain modifiche.json variante.papergrain
PaperAndGrain cli inspect variante.papergrain
```

## Formato della patch

Il file contiene un array di operazioni JSON Patch eseguite nell’ordine indicato. I percorsi JSON Pointer iniziano con `/` e identificano un campo o un elemento del manifest nativo. Gli indici degli array partono da zero. `~1` rappresenta uno slash nel nome del campo e `~0` una tilde. La radice del documento è riservata.

| Operazione | Campi | Effetto |
| --- | --- | --- |
| `test` | `path`, `value` | Richiede che il valore corrisponda. Un test fallito annulla l’intera patch. |
| `add` | `path`, `value` | Imposta un campo o inserisce un elemento nell’array. Il suffisso `/-` accoda. |
| `replace` | `path`, `value` | Sostituisce un valore esistente. |
| `remove` | `path` | Elimina un campo facoltativo o un elemento. |
| `move` | `from`, `path` | Rimuove un valore e lo inserisce alla destinazione, valutata dopo la rimozione. |
| `copy` | `from`, `path` | Copia il valore alla destinazione. Ogni oggetto copiato con un campo `id` (una pagina, un box di testo e quelli che contiene) riceve un nuovo UUID; i riferimenti a quegli ID dentro la copia, come `box:<UUID>` in `layerOrder`, lo seguono. I riferimenti alle foto restano invariati. |

Questa patch richiede una prima pagina con testo «Partenza», modifica il racconto, imposta lo stile del corpo e sposta la pagina in fondo.

```json
[
  {"op":"test","path":"/pages/0/text","value":"Partenza"},
  {"op":"replace","path":"/pages/0/text","value":"Siamo partiti prima dell’alba."},
  {"op":"add","path":"/pages/0/typography","value":{"body":{"pointSize":15,"alignment":"left"}}},
  {"op":"move","from":"/pages/0","path":"/pages/-"}
]
```

## Regole delle pagine ed esito

`patch` e `build` condividono le regole delle pagine. Sono errori un `layout` diverso da quello richiesto da `arrangement` (per esempio `gallery` per `twoAcross`), una foto ripetuta nella stessa pagina e una patch che lascia il libro senza pagine. Come nell’app, le foto oltre la capacità della composizione e il testo su un layout che non lo mostra (`gallery`, `fullPage`, `fullSpread`) restano salvati ma non compaiono: `build` li rifiuta, `patch` li accetta e li segnala.

In caso di successo `patch` restituisce `project`, `id` e `warnings`, un array di messaggi in inglese che riguardano solo le pagine nuove o modificate dalla patch, per esempio `Page 1 (pages[0]) has 3 photos; arrangement "twoAcross" shows 2. The others stay stored but are not shown`.

Prima delle modifiche posizionali, usare `test` su `/pages/0/id` o `/photos/0/id` con il corrispondente UUID ottenuto da `inspect`. Eseguire nuovamente `inspect` sulla variante prima di generare una patch successiva.

## Percorsi del modello

- `/pages` determina l’ordine delle pagine. Per inserire una pagina fornire almeno `id` (un nuovo UUID), `layout`, `photoIDs` e `text`. Per cambiare impaginazione si possono modificare insieme `layout` e `arrangement`. `photoIDs` contiene UUID della libreria del libro nell’ordine degli slot.
- `/pages/0/photoPlacements` segue la rappresentazione nativa Swift delle mappe con chiavi UUID. È un array alternato `["UUID", {"frame": {...}, "crop": {...}}, ...]`. Usare `inspect` per leggere l’ordine e `test` sulla chiave prima di modificare la voce seguente. Ogni chiave deve comparire anche in `photoIDs`. `crop` contiene `x` e `y` tra 0 e 1 e `zoom` tra 1 e 12.
- Le cornici hanno `x`, `y`, `width` e `height` in proporzione alla pagina, con origine in alto a sinistra. Le stesse coordinate si applicano a `titleFrame`, `storyFrame`, `storyBackdropFrames`, ai `textBoxes` e ai due riquadri della copertina. Ogni box di testo ha `id`, `text` e `frame`, con stile tipografico locale facoltativo.
- `/typography`, `/pages/0/typography` e `/cover/typography` accettano `title` e `body`. Ogni stile può specificare `fontName`, `pointSize`, `alignment` (`left`, `center`, `right`, `justified`), `color` e `lineSpacing` (multiplo dell’interlinea da 0.8 a 2).
- Un box di testo in `/pages/0/textBoxes` ha `id`, `text`, `frame` e i campi facoltativi `typography` (uno stile), `usesFullWidth` (testo senza margine interno), `backgroundColor`, `hidesBackground` (box trasparente), `borderColor` e `borderWidth` in punti da 0 a 12.
- I colori sono interi `0xRRGGBB` scritti in decimale, da 0 a 16777215 (`0xFFFFFF`). Senza colore valgono l’inchiostro e la carta del modello. La patch rifiuta colori, `borderWidth` e `lineSpacing` fuori intervallo.
- `/pages/0/layerOrder` elenca gli oggetti della pagina dal fondo verso l’alto come stringhe `story`, `photo:<UUID>` e `box:<UUID>`. Le voci che non corrispondono a un oggetto della pagina vengono ignorate. Gli oggetti non elencati mantengono la posizione predefinita: foto sotto, box sopra.
- `/cover` raccoglie `title`, `spineMM`, `frontPhotoID`, `backPhotoID`, `backText`, `typography`, `frontTitleFrame` e `backTextFrame`. I riferimenti foto devono appartenere al libro.
- `/cover/frontPhotoPlacement` e `/cover/backPhotoPlacement` possono specificare `frame` (coordinate normalizzate `x`, `y`, `width`, `height`) e `crop` (`x` e `y` da 0 a 1, `zoom` da 1 a 12). Se il campo è assente, si usa il posizionamento del modello per la faccia.
- `/film` e `/photos/0/film` contengono `preset`, `strength`, `grain`, `grainSize` e l’eventuale `lutFilename` già presente in `looks`. `/photos/0/adjustments` contiene i valori di sviluppo. Per cambiare un singolo parametro già presente usare ad esempio `replace /photos/0/adjustments/exposure`.
- `/format` imposta `widthMM` e `heightMM`. `/printSettings` raccoglie `bleedMM`, `safeMM`, `targetPPI`, `spreads` e il facoltativo `firstPageOnRight`. `/template` accetta gli identificatori del catalogo `templates`. `/showPageNumbers` accetta un booleano. Rimuovere il campo per ripristinare l’impostazione del modello.

Il catalogo `templates` include i valori iniziali in `defaults.film`, `defaults.adjustments` e `defaults.printSettings`. Si può copiare l’oggetto completo e cambiare i valori desiderati. Per creare un oggetto facoltativo assente, usare `add` sull’intero oggetto con i campi obbligatori del modello. Per ripristinare l’ereditarietà, usare `remove` sul campo facoltativo. La patch verifica i campi e i riferimenti prima della pubblicazione. I comandi di importazione gestiscono le immagini e le LUT. Gli ID foto, i nomi file, le dimensioni originali, le date di acquisizione, gli ID Foto di origine e la versione dello schema sono riservati. Alla lettura, `pixelWidth` e `pixelHeight` devono essere compresi fra 1 e 1.000.000.

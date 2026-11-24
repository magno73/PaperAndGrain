# Comporre un fotolibro dal terminale

Su macOS 14 o successivo, un agente può preparare un libro da una specifica JSON e da immagini locali. L’autore apre il pacchetto prodotto con Paper & Grain e ritrova pagine, foto e testi modificabili.

Dalla radice del repository:

```sh
swift run PaperAndGrain cli templates
swift run PaperAndGrain cli build viaggio.json Viaggio.papergrain
swift run PaperAndGrain cli inspect Viaggio.papergrain
```

Con l’app installata si può invocare direttamente il binario, anche da un’altra directory:

```sh
"/Applications/Paper & Grain.app/Contents/MacOS/PaperAndGrain" cli templates
```

## Specifica versione 1

```json
{
  "version": 1,
  "title": "Quaderno di viaggio",
  "format": { "widthMM": 210, "heightMM": 210 },
  "template": "atlas",
  "assets": [{ "id": "orizzonte", "path": "foto/orizzonte.jpg" }],
  "pages": [
    { "arrangement": "textBesidePhoto", "photos": ["orizzonte"], "heading": "Partenza", "text": "Attraversiamo la pianura al mattino." },
    { "layout": "fullSpread", "photos": ["orizzonte"] }
  ],
  "cover": { "frontPhoto": "orizzonte", "title": "Quaderno di viaggio", "backText": "Appunti dal campo", "spineMM": 4 }
}
```

- Sono obbligatori `version`, un `title` con contenuto, `assets` (anche vuoto) e almeno una voce in `pages`. Il formato predefinito misura 210 × 210 mm. L’assenza di `template` usa lo stile classico dell’app.
- Ogni asset ha un ID univoco e un percorso file assoluto o relativo alla specifica. Il comando copia gli originali nel pacchetto. Gli ID della specifica valgono durante la composizione. L’app assegna UUID alle foto importate.
- L’ordine di `pages` è quello del libro. L’ordine di `photos` assegna gli slot sulla pagina. Una foto può ricorrere su più pagine e in copertina. Ogni pagina accetta una sola occorrenza dello stesso ID.
- `templates` elenca ID dei modelli del libro, tipi di pagina e composizioni con capacità e layout corrispondente. Una pagina priva di `layout` e `arrangement` usa `gallery`. La composizione determina il layout. Con `mixed` e `text` si possono includere `heading` e `text`. `fullSpread` dispone una foto su due facciate.
- La copertina è facoltativa. Accetta `title`, `frontPhoto`, `backPhoto`, `backText` e un dorso `spineMM` in millimetri.

## Contratto dei comandi

`build` richiede una cartella padre esistente e un nuovo percorso con estensione `.papergrain`. Prepara tutto in una cartella temporanea sorella e pubblica il risultato con una rinomina esclusiva. Un errore di importazione o una destinazione già occupata lascia intatti i progetti esistenti. Per rigenerare una variante, scegliere un nuovo nome.

In caso di successo il processo termina con codice 0 e scrive un documento JSON su stdout. `build` restituisce `project` (percorso assoluto) e `id`. `inspect` legge e valida il manifest e restituisce il modello nativo comprensivo di pagine, riferimenti e nomi degli asset. Per gli errori la CLI termina con codice 1 e scrive su stderr un oggetto JSON con il campo `error`. Per separare i messaggi di compilazione di SwiftPM dall’output della CLI, invocare il binario già compilato.

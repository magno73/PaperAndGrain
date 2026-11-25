# Comporre un fotolibro dal terminale

Su macOS 14 o successivo, un agente può creare un libro, importare e analizzare immagini, cambiare l’impaginato, vedere anteprime ed esportare un PDF. I comandi usano lo stesso pacchetto modificabile dell’editor.

Dalla radice del repository:

```sh
swift run PaperAndGrain cli templates
swift run PaperAndGrain cli build viaggio.json Viaggio.papergrain
swift run PaperAndGrain cli inspect Viaggio.papergrain
swift run PaperAndGrain cli help
```

Con l’app installata si può invocare direttamente il binario, anche da un’altra directory:

```sh
"/Applications/Paper & Grain.app/Contents/MacOS/PaperAndGrain" cli templates
```

## Flusso per gli agenti

1. Usa `templates` per leggere modelli, composizioni, capacità e valori iniziali di pellicola, ritaglio, regolazioni e stampa. Usa `build` con una specifica JSON oppure parti da un progetto esistente.
2. Se le foto sono in Apple Foto, usa il binario del bundle firmato. `albums` elenca gli album, `album-assets` le immagini. `import-photos` aggiunge una selezione esplicita alla libreria del progetto. Puoi creare un progetto iniziale con `assets: []` e `pages: [{"layout":"gallery"}]`. [Comandi di importazione e media](cli-media.md)
3. Usa `analyze` per ottenere i dati visuali, `rank` per trovare scatti legati a un brano e `similar` per confrontare due scene o individuare quasi duplicati. `photo-preview` consente di esaminare i candidati.
4. Usa `auto-layout SOURCE.papergrain OUTPUT.papergrain` per rigenerare le pagine in base al giorno di acquisizione e all’ordine delle foto. Quando il libro ha già un impaginato da conservare, parti da `inspect` e usa `patch` per cambiare i campi desiderati. [Modifiche e coordinate](cli-editing.md)
5. Usa `auto-enhance`, `film-looks` e `import-lut` per lo sviluppo colore. Usa `export-pdf` con il profilo `proof`, `print` o `pixart`. [Comandi di sviluppo ed esportazione](cli-media.md)

I comandi di modifica scrivono in una nuova destinazione `.papergrain`. Gli UUID delle immagini e delle pagine già presenti identificano gli stessi elementi nelle varianti, salvo una rimozione o la rigenerazione delle pagine con `auto-layout`. L’ID del libro cambia.

## Catalogo e ricerca delle foto

```sh
PaperAndGrain cli analyze Viaggio.papergrain --output Viaggio-analizzato.papergrain
PaperAndGrain cli photos Viaggio-analizzato.papergrain --details --limit 10
PaperAndGrain cli rank Viaggio-analizzato.papergrain "elefanti alla pozza di Etosha" --unused --limit 8
PaperAndGrain cli similar Viaggio-analizzato.papergrain UUID --by near-duplicate --limit 5
```

- `photos` restituisce UUID, percorso locale, data ISO 8601, dimensioni, pagine, associazioni in copertina, etichette e temi. `--photo UUID` seleziona un’immagine e restituisce i dati completi. `--details` restituisce i dati completi per l’elenco. `--filter QUERY` cerca nel nome e nei dati dell’analisi.
- `analyze` elabora sul Mac le immagini senza analisi recente. Accetta `--photo UUID` più volte e `--force` per ripetere l’analisi. Il risultato contiene esito, dati ed eventuale errore per foto. Per registrare i risultati nel progetto, usa `--output`. Con il solo report puoi conservare i dati nel processo che ha lanciato il comando.
- `rank` restituisce solo candidati con riscontro e include `evidence` con la voce riconosciuta, la fonte (`subject`, `text` o `concept`) e il contributo al punteggio. Il punteggio ordina i candidati. `--unused` esclude foto assegnate a pagine o copertina. Lo stesso filtro vale per `photos` e `similar`.
- `similar --by subjects` confronta le etichette ponderate dalla confidenza. `--by near-duplicate` ordina in base alla distanza tra le impronte visive. I risultati espongono entrambi i valori quando disponibili. Usa le anteprime per valutare gli scatti vicini.

L’analisi di revisione 2 comprende fino a 48 classificazioni con confidenza, persone, volti e animali rilevati, testo riconosciuto con confidenza e riquadro, palette sRGB, orientamento, luminosità, contrasto, dettaglio e impronta visiva. I riquadri Vision sono normalizzati e partono dal basso a sinistra. `unavailableSignals` distingue un modulo indisponibile da una rilevazione vuota. Luminosità, contrasto e dettaglio sono misure sul campione ridotto. Il dettaglio approssima la variazione locale e risente anche della grana. Candidati e rilevamenti sono stime. Il rilevamento dei volti registra la presenza e la posizione.

Il rilevatore animali di Apple Vision localizza cani e gatti. Per la fauna selvatica, `rank` usa le etichette del classificatore dell’intera immagine e i temi associati. [Apple Vision · VNAnimalIdentifier](https://developer.apple.com/documentation/vision/vnanimalidentifier)

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

- Sono obbligatori `version`, un `title` con contenuto, `assets` (anche vuoto) e almeno una voce in `pages`. Il formato predefinito misura 210 × 210 mm. L’assenza di `template` usa lo stile classico dell’app. `showPageNumbers` è un booleano facoltativo che abilita o disabilita la numerazione sulle pagine interne con margini. Se è assente, vale l’impostazione del modello.
- Ogni asset ha un ID univoco e un percorso file assoluto o relativo alla specifica. Il comando copia gli originali nel pacchetto. Gli ID della specifica valgono durante la composizione. L’app assegna UUID alle foto importate.
- L’ordine di `pages` è quello del libro. L’ordine di `photos` assegna gli slot sulla pagina. Una foto può ricorrere su più pagine e in copertina. Ogni pagina accetta una sola occorrenza dello stesso ID.
- `templates` elenca ID dei modelli del libro, tipi di pagina e composizioni con capacità e layout corrispondente. Una pagina priva di `layout` e `arrangement` usa `gallery`. La composizione determina il layout. Con `mixed` e `text` si possono includere `heading` e `text`. `fullSpread` dispone una foto su due facciate. Si può indicare anche come `arrangement` per selezionarla come modello della pagina.
- La copertina è facoltativa. Accetta `title`, `frontPhoto`, `backPhoto`, `backText` e un dorso `spineMM` in millimetri.

## Contratto dei comandi

`build` richiede una cartella padre esistente e un nuovo percorso con estensione `.papergrain`. Prepara tutto in una cartella temporanea sorella e pubblica il risultato con una rinomina esclusiva. Un errore di importazione o una destinazione già occupata lascia intatti i progetti esistenti. Per rigenerare una variante, scegliere un nuovo nome.

In caso di successo il processo termina con codice 0 e scrive un documento JSON su stdout. `build` restituisce `project` (percorso assoluto) e `id`. `inspect` valida e restituisce il manifest originale, mantenendo gli indici esatti necessari a `patch`. Gli errori di comando terminano con codice 1 e scrivono su stderr un oggetto JSON con il campo `error`. Gli esiti parziali dell’analisi compaiono nel report. Per separare i messaggi di compilazione di SwiftPM dall’output della CLI, invocare il binario già compilato.

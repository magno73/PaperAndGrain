# Foto, sviluppo ed esportazione dalla CLI

I comandi usano lo stesso motore di importazione, sviluppo colore ed esportazione dell’app. I percorsi degli argomenti sono assoluti o relativi alla directory corrente. I comandi di modifica creano un nuovo pacchetto `.papergrain` e il progetto sorgente resta disponibile per altre varianti. Le destinazioni richiedono una cartella padre già esistente e un nome libero.

## Apple Foto

Esegui i comandi che accedono a Foto con il binario nel bundle firmato di Paper & Grain, per esempio `"/Applications/Paper & Grain.app/Contents/MacOS/PaperAndGrain" cli albums`. Usa `--request-access` per chiedere al sistema l’autorizzazione iniziale. Con l’accesso limitato i risultati comprendono solo album e foto visibili a Paper & Grain.

- `albums [--request-access]` restituisce gli album accessibili con ID, titolo e numero di immagini.
- `album-assets ALBUM_ID [--request-access]` restituisce gli ID delle immagini nell’album, le dimensioni e l’eventuale data di acquisizione ISO 8601.
- `album-preview ALBUM_ID --asset ID --output FILE.png [--request-access]` salva un’anteprima dell’immagine scelta, se disponibile localmente. Restituisce percorso e dimensioni.

## Importazione

`import-photos SOURCE.papergrain --spec IMPORT.json --output OUTPUT.papergrain [--request-access]` aggiunge immagini alla libreria del progetto, in modo che i nuovi UUID possano essere usati nelle operazioni di impaginazione. Restituisce il percorso del progetto, il suo ID e le nuove voci della libreria nell’ordine di importazione. Se una foto manca o genera un errore, il comando interrompe l’importazione e non pubblica il pacchetto.

La specifica contiene `version: 1` e una o entrambe le selezioni seguenti. I file locali sono relativi alla specifica e precedono la selezione da Foto. Gli originali da Foto possono essere scaricati da iCloud da macOS. Scegli gli ID dopo aver consultato l’album. Per importarlo tutto, includi esplicitamente tutti gli ID desiderati.

La specifica accetta solo `version`, `files` e `photos`, e `photos` solo `albumID` e `assetIDs`. Una chiave sconosciuta interrompe il comando con un errore che la nomina insieme alle chiavi valide.

```json
{
  "version": 1,
  "files": ["./foto/partenza.jpg", "./foto/ritorno.heic"],
  "photos": {
    "albumID": "<ID album>",
    "assetIDs": ["<ID prima foto>", "<ID seconda foto>"]
  }
}
```

## Sviluppo e anteprime

- `photo-preview SOURCE.papergrain --photo UUID --output FILE.png [--max-pixels N] [--original]` esporta un PNG del contenuto della foto con le regolazioni e il look effettivi. Il limite del lato lungo è 1600 pixel per impostazione predefinita e accetta valori da 1 a 8192. Usa `--original` per vedere la foto senza le regolazioni e il look. Il risultato comprende il percorso e le dimensioni effettive.
- `auto-enhance SOURCE.papergrain --photo UUID --output OUTPUT.papergrain` applica la regolazione automatica dell’app alla foto indicata. Restituisce percorso, ID del progetto e i dati della foto aggiornata.
- `film-looks` elenca i preset e le LUT Fujifilm, compreso lo sviluppo di partenza previsto (`linear` o `provia`).
- `import-lut SOURCE.papergrain (--file PATH | --fujifilm LOOK_ID) [--photo UUID] --output OUTPUT.papergrain` installa e applica una LUT 3D `.cube`, Hald CLUT `.png` o Fujifilm inclusa nel bundle. Se ometti `--photo`, la applica al libro. Restituisce percorso, ID del progetto e il nome del nuovo file LUT nel pacchetto.

## PDF

`export-pdf SOURCE.papergrain --profile proof|print|pixart --output PATH [--spine-mm MM]` restituisce il percorso, il profilo e gli avvisi di stampa rilevati. I profili condividono le impostazioni e le risorse del progetto.

- `proof` salva la bozza dell’interno in un singolo `.pdf`.
- `print` salva `Interior.pdf` e, se presente la copertina, `Cover.pdf` in una nuova cartella.
- `pixart` salva un unico `.pdf` con la copertina prima delle pagine interne secondo il profilo cartonato 21 × 21 cm e richiede un libro di 210 × 210 mm. Usa la misura del dorso salvata nel progetto oppure specifica `--spine-mm` con un valore maggiore di 0 e al massimo 100.

Prima di creare file, il comando rifiuta con un errore specifico un libro senza pagine, un formato con un lato di 17,6 mm o meno e una pagina troppo piccola per i suoi margini. `import-lut` indica se il file non è un `.cube` o un `.png` oppure se la dimensione non è compresa fra 1 byte e 50 MB.

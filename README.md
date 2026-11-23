# Paper & Grain

Paper & Grain è un’app Mac per trasformare un album di viaggio in un fotolibro che alterna foto e racconti. Il primo libro di prova è Namibia. La prima build è per macOS 14 o successivo e usa SwiftUI, PhotoKit, Vision e Core Graphics.

## Compilare e aprire

Con Xcode selezionato come toolchain, dalla radice del repository:

```sh
./scripts/build-app.sh
open 'dist/0.2.0/Paper & Grain.app'
```

Lo script raccoglie eseguibile, risorse, traduzioni e configurazione di Foto in un bundle con firma locale. Il percorso include la versione. Se hai già un libro aperto, completa e salva il lavoro nella build corrente prima di aprire un altro bundle. Per la build ottimizzata usare `./scripts/build-app.sh release`. Il progetto SwiftPM si può aprire da Xcode per lavorare sui sorgenti. Usare il bundle per il collaudo di Foto.

## Fare un primo libro

1. Apri **Scegli un album da Foto** e, al primo accesso, autorizza l’app nelle finestre di macOS. Scegli **Namibia**, seleziona le immagini, imposta il formato e premi **Impagina**. **Importa file** accetta immagini dal Finder. Il libro dimostrativo si apre senza accedere alla libreria.
2. Usa le miniature per navigare, aggiungere e riordinare le pagine. Scegli fra **Galleria**, **Pagina di testo**, **Foto e testo**, **Tutta pagina** e **Due pagine**. Nelle composizioni al vivo puoi regolare l’inquadratura. La guida della piega è visibile nell’editor.
3. Scrivi o incolla un racconto nell’ispettore. **Foto suggerite** mostra gli scatti ancora disponibili per la pagina che corrispondono al testo. La scheda **Foto** permette di sfogliare gli scatti per tema.
4. **Salva progetto** crea un pacchetto locale `.papergrain`. **Esporta PDF** produce una prova su pagine singole, anche per una foto che attraversa due pagine. Il globo sceglie lingua di sistema, italiano o inglese.


## Pellicole e stampa

La scheda **Pellicola** applica un look al libro o alla foto selezionata, con intensità, grana e dimensione regolabili. **Originale** permette il confronto. Si possono importare LUT fotografiche 3D CUBE e HaldCLUT PNG. Il pacchetto conserva una copia dei file importati e ogni foto può ereditare il look del libro.

In **Libro e stampa** si possono cambiare formato, bleed, margine, risoluzione desiderata, tipo di PDF e lato della prima pagina. Imposta la copertina con foto di fronte e retro e la larghezza del dorso. **Esporta per la stampa** produce `Interior.pdf` e, se attivata, `Cover.pdf`. L’esportazione segnala foto sotto la risoluzione obiettivo e pagine di compensazione necessarie per i panorami. Usa le misure del prodotto scelto presso la tipografia.

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

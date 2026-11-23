# Paper & Grain

Paper & Grain è un’app Mac per trasformare un album di viaggio in un fotolibro che alterna foto e racconti. Il primo libro di prova è Namibia. La prima build è per macOS 14 o successivo e usa SwiftUI, PhotoKit, Vision e Core Graphics.

## Compilare e aprire

Con Xcode selezionato come toolchain, dalla radice del repository:

```sh
./scripts/build-app.sh
open 'dist/Paper & Grain.app'
```

Lo script raccoglie eseguibile, risorse, traduzioni e configurazione di Foto in un bundle con firma locale. Per la build ottimizzata usare `./scripts/build-app.sh release`. Il progetto SwiftPM si può aprire da Xcode per lavorare sui sorgenti. Usare il bundle per il collaudo di Foto.

## Fare un primo libro

1. Apri **Scegli un album da Foto** e, al primo accesso, autorizza l’app nelle finestre di macOS. Scegli **Namibia**, seleziona le immagini, imposta il formato e premi **Impagina**. **Importa file** accetta immagini dal Finder. Il libro dimostrativo si apre senza accedere alla libreria.
2. Usa le miniature per navigare, aggiungere e riordinare le pagine. Scegli fra **Galleria**, **Pagina di testo**, **Foto e testo**, **Tutta pagina** e **Due pagine**. Nelle composizioni al vivo puoi regolare l’inquadratura. La guida della piega è visibile nell’editor.
3. Scrivi o incolla un racconto nell’ispettore. **Foto suggerite** mostra gli scatti ancora disponibili per la pagina che corrispondono al testo. La scheda **Foto** permette di sfogliare gli scatti per tema.
4. **Salva progetto** crea un pacchetto locale `.papergrain`. **Esporta PDF** produce una prova su pagine singole, anche per una foto che attraversa due pagine. Il globo sceglie lingua di sistema, italiano o inglese.

## Foto e dati del progetto

L’app copia le immagini selezionate nel progetto. Foto può recuperare da iCloud gli originali selezionati quando servono. Vision esegue sul Mac l’analisi delle copie orientate, usando immagini ridotte fino a 640 pixel. Il pacchetto conserva le etichette e i temi. Il confronto col racconto usa etichette e parole in italiano e inglese. In caso di analisi incompleta, l’editor consente di riprovare.

Il libro nasce come bozza nell’area Application Support dell’utente. Il pacchetto che si salva esplicitamente contiene le immagini, l’analisi e il documento. Trattarlo come l’album originale quando lo si condivide. Le foto e gli appunti privati del viaggio Namibia si tengono fuori dal repository.

## Stato e sviluppo

L’impaginazione iniziale usa date di scatto e righe che rispettano le proporzioni. Il confronto con Fotobuch, le pellicole LUT, la grana e i profili specifici di stampa fanno parte delle tappe successive. Il PDF corrente è una prova di impaginazione.

- [Architettura e formato del documento](docs/architecture.md)
- [Collaudi e stato delle funzionalità](docs/status.md)
- [Istruzioni per chi lavora al codice](AGENTS.md)

# Paper & Grain

Editor nativo per fotolibri di viaggio. La prima build gira su macOS 14 o successivo e usa SwiftUI, PhotoKit, Vision e Core Graphics.

## Compila e apri

Con Xcode selezionato come toolchain:

```sh
./scripts/build-app.sh
open 'dist/Paper & Grain.app'
```

Il progetto SwiftPM si può anche aprire con Xcode. Lo script inserisce le traduzioni, la dichiarazione d’accesso a Foto e la firma locale nel bundle.

## Primo libro

Scegli **Scegli un album da Foto**, concedi l’accesso al sistema e apri **Namibia**. Seleziona gli scatti, scegli il formato e premi **Impagina**. Si può provare lo stesso flusso con file dal Finder o con la foto dimostrativa inclusa. Il tasto con il globo cambia l’interfaccia fra italiano e inglese.

L’editor ha navigazione a doppia pagina, testo, box misti, fotografie a tutta pagina e panorami su due pagine. Il progetto si salva in un pacchetto `.papergrain` con manifest, copie fotografiche e analisi. Il pulsante Esporta PDF produce una prova con testo vettoriale e pagine singole.

## Analisi locale

Vision classifica un’anteprima orientata di massimo 640 pixel, una foto alla volta dopo l’importazione. Il libro conserva il risultato, comprese etichette e temi. Il filtro per tema mostra, ad esempio, deserto, acqua o fauna. Digitando o incollando un testo, l’ispettore ordina i suggerimenti combinando etichette e parole chiave italiane e inglesi. I suggerimenti sono editabili tramite la consueta selezione di foto. La selezione originale viene copiata nel progetto. Vision elabora le immagini sul Mac. Foto può scaricare su richiesta da iCloud le immagini selezionate che non sono già sul Mac.

## Stato della build

La bozza è generata da una disposizione in righe che conserva le proporzioni e segue i giorni di scatto. Il confronto con il motore di Fotobuch è una tappa successiva, insieme a LUT e grana, gestione di copertina e profili per stampatore. Il PDF è pronto per il controllo visivo. La compatibilità con un servizio di stampa va verificata sui requisiti del prodotto. I file personali del libro Namibia non fanno parte del repository.

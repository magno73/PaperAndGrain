# Modelli editoriali

Apri un libro e scegli **Libro e stampa → Modelli del libro**. La finestra mostra i quattro modelli con una foto del progetto. **Applica modello** salva la scelta del libro. Il modello cambia carta, titoli, corpo tipografico, margini e spazi fra foto. L’ordine di pagine e immagini, le inquadrature e i testi si conservano. Il titolo di pagina è facoltativo e si inserisce dall’ispettore nelle pagine di testo o miste.

| Modello | Composizione | Quando sceglierlo |
|---|---|---|
| Diario | Avorio caldo, titoli in Didot e testo in Baskerville | Il racconto conduce le aperture e una foto gli risponde di fronte. |
| Atlante | Carta chiara, Avenir Next, griglia con filetto e numero di pagina | Il viaggio si legge per tappe, con immagini e annotazioni sulla stessa doppia. |
| Galleria | Carbone, titoli in Baskerville Corsivo, testo in Optima e ampi margini | Il libro lascia spazio alle foto singole e ai panorami. |
| Essenziale | Bianco, Helvetica Neue Light per i titoli, testo in Helvetica Neue e fotografia al vivo in copertina | La composizione riprende la sobrietà delle presentazioni Apple. Si presta a doppie con un breve testo accanto a una foto a piena pagina. |

`Book.template` e `BookPage.heading` sono campi facoltativi nello schema v1. Un progetto senza modello usa lo stile di base. `BookTemplate.swift` contiene colori, caratteri e regole condivise tra editor e PDF. Core Text disegna e misura il testo con gli stessi parametri nei due percorsi. Il margine del modello rispetta anche quello minimo di stampa. I PDF della copertina adottano la composizione del modello.

Le tavole Namibia sono state ricavate dagli export reali con foto illustrative create tramite lo strumento integrato ImageGen. I prompt descrivevano una duna del NamibRand con una cresta curva, due escursionisti lontani e luce calda laterale, e un ritratto verticale di un orice fra erbe chiare e montagne malva. Le foto dell’album personale si selezionano in Foto durante l’uso dell’app.

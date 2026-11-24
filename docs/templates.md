# Modelli editoriali

Apri un libro e scegli **Libro e stampa → Modelli del libro**. La finestra mostra i sette modelli con una foto del progetto. **Applica** salva la scelta del libro. **Mostra numeri di pagina** attiva o disattiva i numeri sulle pagine interne con margini, nell’editor e nel PDF. La scelta fatta nella finestra prevale sull’impostazione predefinita del modello. Il modello cambia carta, titoli, corpo tipografico, margini e spazi fra foto. L’ordine di pagine e immagini, le inquadrature e i testi si conservano. Il titolo di pagina è facoltativo e si inserisce dall’ispettore nelle pagine di testo o miste.

| Modello | Composizione | Quando sceglierlo |
|---|---|---|
| Diario | Avorio caldo, titoli in Didot e testo in Baskerville | Il racconto conduce le aperture e una foto gli risponde di fronte. |
| Atlante | Carta chiara, Avenir Next, griglia con filetto e numero di pagina | Il viaggio si legge per tappe, con immagini e annotazioni sulla stessa doppia. |
| Galleria | Carbone, titoli in Baskerville Corsivo, testo in Optima e ampi margini | Il libro lascia spazio alle foto singole e ai panorami. |
| Essenziale | Bianco, Helvetica Neue Light per i titoli, testo in Helvetica Neue e fotografia al vivo in copertina | La composizione riprende la sobrietà delle presentazioni Apple. Si presta a doppie con un breve testo accanto a una foto a piena pagina. |
| Griglia svizzera | Titoli compatti in Helvetica Neue Bold, barra rossa e folio. Il testo occupa cinque colonne di sei. La foto di copertina occupa le quattro colonne di destra. | Un itinerario per tappe, con testi brevi e immagini da leggere in sequenza. |
| Quaderno berlinese | Blu notte, titoli cedro in Avenir Next Condensed Heavy e corpo chiaro in Georgia. La foto occupa quasi due terzi della copertina sopra la testata. Il racconto comincia nel secondo terzo della pagina. | Alterna fotografie ravvicinate e pagine narrative dal ritmo di una rivista indipendente. |
| Intervallo giapponese | Carta calda, titolo in Hiragino Mincho e testo in Palatino. Una piccola stampa occupa il lato destro. Anche il blocco di lettura si sposta a destra e lascia vuoto il quinto superiore della pagina. | Immagini che richiedono una pausa, accompagnate da brevi testi di osservazione. |

Nelle gallerie automatiche, Griglia svizzera allinea le fotografie in celle modulari. Quaderno berlinese dà rilievo alla prima foto con una striscia laterale di immagini più piccole. Intervallo giapponese dispone fino a tre stampe sfalsate, con ampio spazio fra loro.

Nelle pagine **Testo sulla foto**, Griglia svizzera usa un riquadro chiaro con barra rossa verticale, Quaderno berlinese una testata blu notte con bordo giallo cedro e Intervallo giapponese un riquadro color carta con un breve filetto verde muschio. Il selettore mostra questi tre trattamenti sulla stessa foto di copertina.

Per i tre modelli, il titolo automatico riduce leggermente il corpo quando basta a tenere su una riga una frase breve. Un invio scritto dall’autore, un titolo lungo o un corpo in punti scelto nell’ispettore conserva la propria impaginazione.

Griglia svizzera riprende la tradizione tipografica di Zurigo. [Museum für Gestaltung Zürich](https://eshop.museum-gestaltung.ch/?lang=en&nr=780030&op=productnr)

Quaderno berlinese interpreta il lavoro per vincoli attraverso il contrasto fra testata condensata, testo letterario e fascia fotografica. [Laboratori di Hort](https://hort.org.uk/wp-content/uploads/2014/11/Hort-Workshops.pdf)

Intervallo giapponese usa lo spazio vuoto come invito all’interpretazione. [White di Kenya Hara](https://www.lars-mueller-publishers.com/white)

`Book.template` e `BookPage.heading` sono campi facoltativi nello schema v1. Un progetto senza modello usa lo stile di base. `BookTemplate.swift` contiene colori, caratteri e regole condivise tra editor e PDF. Core Text disegna e misura il testo con gli stessi parametri nei due percorsi. Il margine del modello rispetta anche quello minimo di stampa. I PDF della copertina adottano la composizione del modello.

Le tavole Namibia sono state ricavate dagli export reali con foto illustrative create tramite lo strumento integrato ImageGen. I prompt descrivevano una duna del NamibRand con una cresta curva, due escursionisti lontani e luce calda laterale, e un ritratto verticale di un orice fra erbe chiare e montagne malva. Le foto dell’album personale si selezionano in Foto durante l’uso dell’app.

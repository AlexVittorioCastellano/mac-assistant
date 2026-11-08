import Foundation

/// Funzione 4: chat libera su come fare cose sul Mac.
///
/// Il modello on-device è piccolo e può sbagliare scorciatoie o percorsi di
/// menu. Per gli argomenti più comuni gli passiamo una "guida" verificata
/// (`MacHowTo`), scelta dal codice in base alle parole della domanda.
public enum MacHelpChat {

    public static var instructions: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Prompts.base + """

        Aiuti a usare il Mac (macOS \(version.majorVersion)). Rispondi a domande su come fare le cose.
        Quando servono più azioni, usa passi numerati brevi (al massimo 5).
        Usa i nomi italiani di menu, tasti e impostazioni (es. Impostazioni di Sistema, Finder, Cestino).
        Se ricevi una «guida verificata», seguila: è corretta.
        Copia le scorciatoie da tastiera ESATTAMENTE come sono scritte nella guida, con tutti i simboli (⌘ ⇧ ⌥ ⌃).
        Se non sei sicuro di dove si trova un'impostazione, dillo e suggerisci di cercarla \
        nel campo di ricerca di Impostazioni di Sistema o con Spotlight (⌘ Spazio).
        Rispondi direttamente, senza premesse.
        Solo se la domanda non ha niente a che fare con computer e tecnologia, rispondi in una frase \
        che puoi aiutare solo con il Mac.
        """
    }

    /// Le guide verificate pertinenti alla domanda.
    public static func guides(for question: String) -> [String] {
        MacHowTo.matching(question)
    }

    /// Il messaggio da inviare al modello: la domanda, più le guide pertinenti.
    public static func prompt(for question: String) -> String {
        let guides = guides(for: question)
        guard !guides.isEmpty else { return question }
        return question + "\n\nGuida verificata (usala se è pertinente):\n"
            + guides.map { "- \($0)" }.joined(separator: "\n")
    }
}

extension MacHelpChat {
    /// Rete di sicurezza: `true` se la risposta contiene una scorciatoia da
    /// tastiera che non compare nelle guide verificate (es. "⌘ e 3" invece di
    /// "⌘⇧3"). In quel caso l'interfaccia mostra anche la guida esatta.
    public static func answerNeedsGuide(_ answer: String, guides: [String]) -> Bool {
        guard !guides.isEmpty else { return false }
        let allowed = Set(guides.flatMap(shortcuts))
        return shortcuts(in: answer).contains { !allowed.contains($0) }
    }

    /// Scorciatoie in un testo: simboli dei tasti seguiti dal tasto
    /// (es. "⌘⇧4", "⌥⌘Esc"; "⌘" da solo se manca il tasto).
    static func shortcuts(in text: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        let stops: Set<Character> = [" ", "\n", ".", ",", ";", ":", ")", "»", "*", "("]
        var result: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard modifiers.contains(text[i]) else { i = text.index(after: i); continue }
            var j = i
            while j < text.endIndex, !stops.contains(text[j]) { j = text.index(after: j) }
            result.append(String(text[i..<j]))
            i = j
        }
        return result
    }
}

/// Istruzioni brevi e verificate per le domande più comuni.
/// Contributi benvenuti! Regole: solo cose certe e valide da diverse versioni
/// di macOS; parole chiave senza accenti e in minuscolo. Una parola chiave
/// con "+" richiede tutte le parti, in qualunque ordine (es. "iphone+file").
public enum MacHowTo {
    struct Entry {
        let keywords: [String]
        let text: String
    }

    static let entries: [Entry] = [
        .init(keywords: ["screenshot", "schermata", "catturare lo schermo", "foto dello schermo"],
              text: "Screenshot: ⌘⇧3 cattura tutto lo schermo; ⌘⇧4 una parte (trascina per selezionare); ⌘⇧4 e poi Spazio cattura una finestra; ⌘⇧5 apre il pannello con tutte le opzioni. Le immagini vanno sulla Scrivania."),
        .init(keywords: ["registr+schermo", "video dello schermo"],
              text: "Registrare lo schermo: premi ⌘⇧5 e scegli «Registra tutto lo schermo» o «Registra parte selezionata». Per fermare, clicca il pulsante di stop nella barra dei menu."),
        .init(keywords: ["non risponde", "uscita forzata", "forza", "bloccat+app", "bloccat+programma", "impallat"],
              text: "App che non risponde: premi ⌥⌘Esc, scegli l'app e clicca «Uscita forzata». Le modifiche non salvate in quell'app si perdono."),
        .init(keywords: ["spotlight", "cercare un file", "trovare un file", "cerco un file", "trovare un'app"],
              text: "Cercare: premi ⌘ Spazio per aprire Spotlight e scrivi il nome del file, dell'app o dell'impostazione."),
        .init(keywords: ["disinstall", "elimin+app", "rimuov+app", "cancell+app", "togl+app", "tolg+app", "elimin+programma", "rimuov+programma", "cancell+programma", "togl+programma", "tolg+programma"],
              text: "Disinstallare un'app: apri la cartella Applicazioni nel Finder e trascina l'app nel Cestino (o clic destro → Sposta nel Cestino), poi svuota il Cestino."),
        .init(keywords: ["file nascost", "cartelle nascost"],
              text: "File nascosti: nel Finder premi ⌘⇧. (punto) per mostrarli o nasconderli."),
        .init(keywords: ["copia e incolla", "copi+testo", "incoll", "spost+file", "copi+file"],
              text: "Copia e incolla: ⌘C copia, ⌘X taglia (nel testo), ⌘V incolla. Per spostare un file nel Finder: ⌘C sul file, poi ⌥⌘V nella cartella di destinazione."),
        .init(keywords: ["emoji", "faccine"],
              text: "Emoji: premi il tasto 🌐 (Fn) + E, oppure ⌃⌘Spazio."),
        .init(keywords: ["rinomin+file", "rinomin+cartell", "cambiare nome+file"],
              text: "Rinominare un file: selezionalo nel Finder, premi Invio, scrivi il nuovo nome e premi di nuovo Invio."),
        .init(keywords: ["comprim", "zip", "archivio compresso"],
              text: "Comprimere: clic destro sul file o sulla cartella → «Comprimi». Per aprire uno .zip basta un doppio clic."),
        .init(keywords: ["aggiorn+mac", "aggiorn+app", "aggiornament"],
              text: "Aggiornare macOS: Impostazioni di Sistema → Generali → Aggiornamento Software. Le app dell'App Store si aggiornano dall'App Store."),
        .init(keywords: ["backup", "time machine"],
              text: "Backup con Time Machine: collega un disco esterno, poi Impostazioni di Sistema → Generali → Time Machine → «Aggiungi disco di backup»."),
        .init(keywords: ["batteria", "autonomia"],
              text: "Batteria: Impostazioni di Sistema → Batteria mostra lo stato di salute della batteria e quanto consumano le app."),
        .init(keywords: ["password del wi", "password wifi", "password wi-fi", "password della rete"],
              text: "Vedere la password del Wi‑Fi: Impostazioni di Sistema → Wi‑Fi → «Dettagli…» accanto alla rete → «Copia password»."),
        .init(keywords: ["modalita scura", "tema scuro", "dark mode", "modalita chiara"],
              text: "Modalità scura: Impostazioni di Sistema → Aspetto → Chiaro, Scuro o Automatico."),
        .init(keywords: ["ingrand+testo", "ingrand+scritt", "ingrandi+caratter", "scritte piccole", "testo piccolo", "piu grand+testo", "piu grand+scritt"],
              text: "Testo più grande: Impostazioni di Sistema → Monitor → scegli una risoluzione «più grande». Nel browser: ⌘+ ingrandisce, ⌘− rimpicciolisce."),
        .init(keywords: ["affianc", "dividere lo schermo", "split view", "due finestre", "meta schermo"],
              text: "Affiancare finestre: passa il mouse sul pulsante verde in alto a sinistra della finestra e scegli una disposizione, oppure trascina la finestra verso il bordo dello schermo."),
        .init(keywords: ["elementi login", "app+avvio", "app+accension", "programm+avvio", "programm+accension", "si apre da sola", "si aprono da sole", "partono da sole"],
              text: "App all'avvio: Impostazioni di Sistema → Generali → Elementi login; togli con «−» le app che non vuoi all'accensione."),
        .init(keywords: ["app predefinita", "programma predefinito", "aprire sempre con", "apri con"],
              text: "Cambiare l'app che apre un tipo di file: clic destro sul file → Ottieni informazioni → «Apri con» → scegli l'app → «Cambia tutto…»."),
        .init(keywords: ["airdrop", "iphone+file", "iphone+foto", "iphone+video", "ipad+file", "ipad+foto", "ipad+video", "telefono+file"],
              text: "AirDrop: clic destro sul file → Condividi → AirDrop, poi scegli il dispositivo. Sul dispositivo vicino servono Wi‑Fi e Bluetooth attivi."),
        .init(keywords: ["bluetooth", "cuffie", "airpods", "collegare il mouse", "collegare la tastiera"],
              text: "Collegare un dispositivo Bluetooth: mettilo in modalità di abbinamento, poi Impostazioni di Sistema → Bluetooth → «Collega» accanto al dispositivo."),
        .init(keywords: ["dettatura", "dettare", "dett+voce", "scriv+voce", "scriv+parlando"],
              text: "Dettatura: attivala in Impostazioni di Sistema → Tastiera → Dettatura; poi premi il tasto microfono (o due volte Fn) e parla."),
        .init(keywords: ["mission control", "scrivanie", "desktop multipl"],
              text: "Più scrivanie: apri Mission Control (F3 o scorri in alto con tre dita) e clicca «+» in alto a destra."),
        .init(keywords: ["stamp"],
              text: "Stampare: ⌘P. Aggiungere una stampante: Impostazioni di Sistema → Stampanti e scanner → «Aggiungi stampante, scanner o fax…»."),
        .init(keywords: ["sfondo"],
              text: "Cambiare lo sfondo: Impostazioni di Sistema → Sfondo, poi scegli un'immagine. Puoi anche fare clic destro su una foto nel Finder → «Imposta immagine scrivania»."),
        .init(keywords: ["salvaschermo", "screensaver", "salva schermo"],
              text: "Salvaschermo: Impostazioni di Sistema → Salvaschermo."),
        .init(keywords: ["notifiche"],
              text: "Notifiche: Impostazioni di Sistema → Notifiche, poi scegli l'app per decidere se e come mostrare le sue notifiche."),
        .init(keywords: ["volume", "audio", "altoparlant", "suono", "suoni", "avvisi sonori"],
              text: "Audio: Impostazioni di Sistema → Suono per scegliere uscita, ingresso e volume; il suono degli avvisi si sceglie nella sezione «Effetti sonori» della stessa pagina. Il volume si cambia anche dal Centro di Controllo nella barra dei menu."),
        .init(keywords: ["scaricat", "download"],
              text: "File scaricati: sono nella cartella Download. Nel Finder clicca «Download» nella barra laterale, oppure premi ⌥⌘L."),
        .init(keywords: ["nome del mac", "nome del computer", "rinominare il mac"],
              text: "Nome del Mac: Impostazioni di Sistema → Generali → Info, poi modifica il campo «Nome»."),
        .init(keywords: ["monitor", "secondo schermo", "schermo esterno", "proiettore"],
              text: "Secondo monitor: collega il cavo (USB‑C/Thunderbolt o HDMI) e il Mac lo riconosce da solo. Per disporre gli schermi o scegliere quello principale: Impostazioni di Sistema → Monitor."),
        .init(keywords: ["lingua"],
              text: "Lingua del Mac: Impostazioni di Sistema → Generali → Lingua e Zona; aggiungi la lingua con «+» e trascinala in cima alla lista. Serve un riavvio per applicarla ovunque."),
        .init(keywords: ["svuot+cestino"],
              text: "Svuotare il Cestino: clic destro sull'icona del Cestino nel Dock → «Svuota il Cestino»."),
    ]

    /// Le guide pertinenti alla domanda (al massimo 2, per non riempire il contesto).
    static func matching(_ question: String) -> [String] {
        let text = IntentRouter.normalize(question)
        func matches(_ keyword: String) -> Bool {
            keyword.split(separator: "+").allSatisfy { text.contains($0) }
        }
        return Array(entries.filter { $0.keywords.contains(where: matches) }.prefix(2).map(\.text))
    }
}

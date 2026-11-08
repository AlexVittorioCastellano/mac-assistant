/// Brevi spiegazioni di processi comuni di macOS.
///
/// Il modello on-device è piccolo e spesso non conosce questi nomi: queste
/// note gli danno una base corretta. Contributi benvenuti! Regole:
/// - una frase breve, in italiano semplice, senza gergo;
/// - solo informazioni di cui si è sicuri.
public enum KnownProcesses {
    public static let notes: [String: String] = [
        // Cuore del sistema
        "kernel_task": "il cuore di macOS; se usa molto processore spesso sta rallentando il Mac apposta per raffreddarlo",
        "launchd": "avvia e controlla tutti gli altri processi di macOS",
        "loginwindow": "gestisce l'accesso e la sessione dell'utente; chiuderlo fa uscire dalla sessione",
        "WindowServer": "disegna tutto ciò che si vede sullo schermo; lavora di più con tanti monitor o finestre",
        "logd": "raccoglie i messaggi di registro del sistema",
        "configd": "gestisce la rete e la configurazione del sistema",
        "powerd": "gestisce l'energia, la batteria e lo stop",
        "runningboardd": "decide quante risorse dare a ogni app",
        "cfprefsd": "legge e salva le impostazioni delle app",
        "distnoted": "fa passare messaggi interni tra i programmi",
        "UserEventAgent": "reagisce a eventi del sistema (es. collegare un dispositivo)",
        "fseventsd": "tiene traccia delle modifiche ai file, per Time Machine e Spotlight",
        "diskarbitrationd": "gestisce dischi e chiavette collegati",
        // Interfaccia
        "Finder": "l'app per sfogliare file e cartelle; se la chiudi si riapre da sola",
        "Dock": "il Dock e la gestione delle finestre a tutto schermo",
        "SystemUIServer": "alcune icone della barra dei menu",
        "ControlCenter": "Centro di Controllo e alcune icone della barra dei menu",
        "NotificationCenter": "le notifiche",
        // Ricerca e analisi
        "mds": "Spotlight che indicizza i file; di solito si calma da solo dopo un po'",
        "mds_stores": "Spotlight che indicizza i file; di solito si calma da solo dopo un po'",
        "mdworker_shared": "Spotlight che legge i file per la ricerca; temporaneo",
        "corespotlightd": "Spotlight che indicizza i contenuti delle app",
        "photoanalysisd": "Foto che analizza le immagini (volti, oggetti); lavora quando il Mac è inattivo",
        "mediaanalysisd": "analizza foto e video per la ricerca; lavora quando il Mac è inattivo",
        "suggestd": "prepara suggerimenti (es. contatti ed eventi trovati in Mail e Messaggi)",
        // iCloud, rete, dispositivi
        "bird": "sincronizzazione di iCloud Drive",
        "cloudd": "sincronizzazione di iCloud",
        "cloudphotod": "sincronizzazione di Foto con iCloud",
        "photolibraryd": "gestisce la libreria di Foto",
        "nsurlsessiond": "download e upload in background per app e sistema",
        "sharingd": "AirDrop, Handoff e condivisione",
        "rapportd": "comunicazione tra i tuoi dispositivi Apple (Handoff, Continuità)",
        "bluetoothd": "il Bluetooth",
        "airportd": "il Wi-Fi",
        "locationd": "i servizi di localizzazione",
        "coreaudiod": "l'audio del Mac",
        "akd": "l'account Apple",
        // Aggiornamenti, backup, sicurezza
        "backupd": "Time Machine che sta facendo un backup",
        "softwareupdated": "controllo o download degli aggiornamenti di macOS",
        "trustd": "verifica i certificati di sicurezza di siti e app",
        "securityd": "gestisce password e portachiavi",
        "syspolicyd": "controllo di sicurezza delle app appena aperte o scaricate",
        "XProtect": "antivirus integrato di macOS",
        "xprotectd": "antivirus integrato di macOS",
        // Apple Intelligence
        "modelmanagerd": "gestisce i modelli di intelligenza artificiale di Apple Intelligence",
        "TGOnDeviceInferenceProviderService": "fa funzionare il modello di Apple Intelligence sul Mac (lo usa anche questa app)",
        // Web
        "com.apple.WebKit.WebContent": "le pagine web aperte in Safari o in altre app",
        "Spotlight": "la ricerca di Spotlight",
    ]

    /// Cerca la nota ignorando maiuscole/minuscole.
    public static func note(for name: String) -> String? {
        notes[name] ?? notes.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

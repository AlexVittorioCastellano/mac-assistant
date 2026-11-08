/// Brevi spiegazioni di processi di sistema comuni.
///
/// Il modello on-device è piccolo e a volte non conosce questi nomi: queste
/// note lo aiutano a dare risposte corrette. Saranno ampliate dalla
/// funzione "Cos'è questo processo?". Contributi benvenuti!
public enum KnownProcesses {
    public static let notes: [String: String] = [
        "kernel_task": "parte di macOS; se usa molto processore spesso sta rallentando il Mac apposta per raffreddarlo",
        "WindowServer": "disegna tutto ciò che si vede sullo schermo; lavora di più con tanti monitor o finestre",
        "mds_stores": "Spotlight che indicizza i file; di solito si calma da solo dopo un po'",
        "mds": "Spotlight che indicizza i file; di solito si calma da solo dopo un po'",
        "mdworker_shared": "Spotlight che legge i file per la ricerca; temporaneo",
        "photoanalysisd": "Foto che analizza le immagini (volti, oggetti); lavora quando il Mac è inattivo",
        "backupd": "Time Machine che sta facendo un backup",
        "bird": "sincronizzazione di iCloud Drive",
        "cloudd": "sincronizzazione di iCloud",
        "softwareupdated": "controllo o download degli aggiornamenti di macOS",
        "com.apple.WebKit.WebContent": "le pagine web aperte in Safari o in altre app",
        "Spotlight": "la ricerca di Spotlight",
        "syspolicyd": "controllo di sicurezza delle app appena aperte o scaricate",
        "XProtect": "antivirus integrato di macOS",
        "xprotectd": "antivirus integrato di macOS",
    ]
}

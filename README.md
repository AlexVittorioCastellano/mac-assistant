# Assistente Mac

🇮🇹 [Italiano](#italiano) · 🇬🇧 [English](#english)

---

## Italiano

**Assistente Mac** è un'app open source che vive nella barra dei menu del Mac.
Fai una domanda in italiano sul tuo Mac e ricevi una risposta chiara e veloce.

- 🔒 **Tutto resta sul tuo Mac**: usa il modello AI on-device di Apple
  (Apple Intelligence). Nessun dato viene inviato in rete, niente telemetria.
- 🆓 **Gratis e senza chiavi API.**
- 🛡️ **Non tocca nulla da solo**: legge i dati del sistema, non chiude
  programmi e non cancella file.

### Cosa sa fare

| Funzione | Stato |
|---|---|
| **"Controlla il mio Mac"**: un semaforo in un clic su velocità, spazio, backup di Time Machine, cifratura (FileVault), Gatekeeper, SIP, firewall, aggiornamenti e batteria | ✅ |
| **Avvisi automatici**: se un problema dura (un'app che occupa il processore da 10 minuti, memoria esaurita, Mac caldo, disco quasi pieno) arriva una notifica in italiano e l'icona nella barra dei menu cambia. Si spengono con l'interruttore «Avvisi» | ✅ |
| "Perché il Mac è lento?": legge processore, memoria, temperatura e processi e spiega cosa succede | ✅ |
| "Cos'è questo processo?": dice cos'è, se fa parte di macOS o di un'app e se si può chiudere | ✅ |
| "Dove è finito lo spazio?": divide lo spazio occupato in voci (modelli di Apple Intelligence, app, Download, cache…) e spiega i "Dati di sistema" | ✅ |
| Chat libera su come fare cose sul Mac, con guide verificate per le domande più comuni | ✅ |

### Requisiti

- macOS 27 o successivo, Mac con Apple Silicon
- Apple Intelligence attiva (Impostazioni di Sistema → Apple Intelligence e Siri).
  Senza, l'app mostra comunque i problemi trovati e i consigli, ma non la spiegazione.

### Compilare

Bastano i **Command Line Tools** (`xcode-select --install`); Xcode è facoltativo.

```sh
git clone <url-del-repository>
cd AssistenteMac
./scripts/crea-app.sh          # crea build/AssistenteMac.app
open build/AssistenteMac.app
```

Per sviluppare:

```sh
swift run AssistenteMac                         # avvia l'app nella barra dei menu
swift run assistente-cli "Perché il Mac è lento?"   # prova dal terminale
swift run assistente-cli --prompt               # mostra anche il prompt inviato al modello
swift run assistente-cli --chat "Come faccio uno screenshot?"   # chat (altre domande una per riga)
swift run assistente-cli --guide "Come mando un file all'iPhone?"  # quale guida verificata si attiva
ASSISTENTE_AVVISI_RAPIDI=1 swift run AssistenteMac  # avvisi con tempi di pochi secondi, per provarli
./scripts/test.sh                               # esegue i test (veloci, senza AI)
swift run assistente-cli --eval Evals/casi.json # prove di qualità con il modello vero (~5 min)
```

Con Xcode: apri la cartella (o `Package.swift`) e scegli lo schema `AssistenteMac`.

### Come è fatto

```
Sources/
  AssistenteCore/          logica, senza interfaccia (testabile)
    System/                raccolta dati di sistema (solo lettura)
    AI/                    protocollo AIProvider + LocalProvider (on-device)
    Features/              le funzioni: regole, prompt, smistamento domande
  AssistenteMac/           interfaccia SwiftUI (MenuBarExtra)
  assistente-cli/          strumento da terminale per sviluppatori
Tests/AssistenteCoreTests/ test (Swift Testing)
```

Principi:

1. **Dati, AI e interfaccia sono separati.** L'interfaccia parla solo con
   `Assistant`; l'AI sta dietro il protocollo `AIProvider`.
2. **I fatti li calcola il codice, l'AI li spiega.** Numeri, problemi e
   consigli sono prodotti da regole deterministiche (`SlowMacDiagnosis`).
   Il modello on-device è piccolo: gli chiediamo solo di spiegare in italiano
   semplice. Così non può inventare dati né suggerire azioni pericolose
   (per esempio chiudere processi di macOS).
   Se un processo fa parte di macOS lo decidono il percorso e la firma digitale
   di Apple (`ProcessKind`), non il modello.
3. **Pronto per il cloud, senza segreti nel codice.** In futuro potrà esistere
   un `CloudProvider` opzionale che parla con un backend separato dopo il login
   dell'utente. Il client non conterrà mai chiavi: autenticazione e limiti li
   verifica il server. Configurazioni sensibili → file esclusi da git
   (vedi `.gitignore`).

### Contribuire

I contributi sono benvenuti! Alcune idee semplici per iniziare:

- aggiungere spiegazioni in `Features/KnownProcesses.swift` (una frase semplice, solo cose certe);
- aggiungere guide in `Features/MacHelpChat.swift` (`MacHowTo`): istruzioni brevi e
  verificate che la chat usa per non sbagliare scorciatoie e menu. Controlla le
  parole chiave con `swift run assistente-cli --guide "la tua domanda"`;
- migliorare le parole chiave in `Features/IntentRouter.swift`;
- aggiungere test in `Tests/`.

Regole:

- risposte all'utente sempre in italiano, brevi e senza gergo;
- l'app non deve mai chiudere processi o cancellare file senza conferma esplicita;
- nessun dato deve lasciare il Mac in modalità locale; niente telemetria;
- mai committare chiavi, token o URL privati;
- prima di aprire una pull request: `./scripts/test.sh`; se tocchi la chat, le guide
  o lo smistamento delle domande, anche `swift run assistente-cli --eval Evals/casi.json`
  (servono Apple Intelligence attiva). Se trovi una domanda a cui l'app risponde
  male, aggiungila a `Evals/casi.json`: è il modo migliore per non farla più sbagliare.

### Limiti noti

- La chat usa un modello piccolo che lavora sul Mac: per gli argomenti coperti
  dalle guide verificate le risposte sono molto più affidabili (etichetta verde «Basata su una guida dell'app»);
  per gli altri può sbagliare nomi di menu o pulsanti. Se una risposta contiene
  una scorciatoia diversa da quella della guida, l'app mostra la guida esatta.
- La prima volta che misuri lo spazio, macOS può chiedere il permesso di
  leggere le cartelle Download, Documenti e Scrivania. Se lo neghi, quelle voci
  vengono saltate. Le cartelle dei dati di altre app (`~/Library/Containers`)
  non vengono lette: finiscono nella voce "Dati di altre app e file sparsi".
- `kernel_task` (e pochi altri processi del kernel) non è leggibile senza
  permessi di amministratore: il suo carico rientra comunque nel totale del
  processore e nella temperatura.

### Licenza

[MIT](LICENSE)

---

## English

**Assistente Mac** is an open source macOS menu bar app. Ask a question about
your Mac in Italian and get a clear, quick answer. (The app's interface and
answers are in Italian by design.)

- 🔒 **Everything stays on your Mac**: it uses Apple's on-device model
  (Foundation Models / Apple Intelligence). No network, no telemetry.
- 🆓 **Free, no API keys.**
- 🛡️ **Read-only**: it never quits processes or deletes files on its own.

### Features

| Feature | Status |
|---|---|
| **"Check my Mac"**: one-click traffic light for speed, disk space, Time Machine backup, FileVault, Gatekeeper, SIP, firewall, updates and battery health | ✅ |
| **Automatic alerts**: a notification (and a different menu bar icon) when a problem lasts — an app hogging the CPU for 10 minutes, memory exhausted, Mac overheating, disk almost full. Toggle with «Avvisi» | ✅ |
| "Why is my Mac slow?": reads CPU, memory, thermal state and processes, and explains | ✅ |
| "What is this process?": what it is, whether it belongs to macOS or an app, and whether it's safe to quit | ✅ |
| "Where did my disk space go?": breaks down used space (Apple Intelligence models, apps, Downloads, caches…) and explains "System Data" | ✅ |
| Free-form chat about using the Mac, backed by verified guides for common questions | ✅ |

### Requirements

- macOS 27+, Apple Silicon
- Apple Intelligence enabled (without it, the app still shows the detected issues
  and the advice, but not the AI explanation).

### Building

Only the **Command Line Tools** are required; Xcode is optional.

```sh
./scripts/crea-app.sh          # builds build/AssistenteMac.app
open build/AssistenteMac.app

swift run AssistenteMac        # run the menu bar app
swift run assistente-cli       # try features from the terminal (--prompt shows the model prompt)
./scripts/test.sh              # run unit tests (fast, no AI)
swift run assistente-cli --eval Evals/casi.json   # quality evals with the real on-device model
```

### Architecture

- `AssistenteCore/System`: system data collection (read-only)
- `AssistenteCore/AI`: `AIProvider` protocol + `LocalProvider` (on-device).
  A future optional `CloudProvider` will talk to a separate backend via user
  sign-in; the client will never ship keys or secrets.
- `AssistenteCore/Features`: deterministic rules, prompt building, intent routing.
  **Code computes the facts and the advice; the model only explains them.**
- `AssistenteMac`: SwiftUI `MenuBarExtra` UI.

### Contributing

PRs welcome. Keep user-facing text in plain Italian, never quit processes or
delete files without explicit user confirmation, never send data off-device in
local mode, never commit secrets. Run `./scripts/test.sh` before opening a PR.

### License

[MIT](LICENSE)

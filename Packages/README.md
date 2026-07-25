# Aizen Reignition packages

Packages use explicit product boundaries rather than app-global services.

| Package | May depend on | Must not depend on |
| --- | --- | --- |
| Core | Foundation | UI, persistence, ACP, platform APIs |
| Wire | Core | persistence, UI, platform APIs |
| Client | Core, Wire, Transport | Host, Storage, MacPlatform |
| Features | Core, Client | Core Data, ACP, Host implementations |
| Design | SwiftUI | Host, Storage, MacPlatform |
| Host | Core, Wire, host contracts | UI clients |
| Storage | Core | Mobile |
| Security | Core, Wire | host-only platform adapters |
| Transport | Wire | domain authorisation |
| MacPlatform | Core | Mobile |
| TestSupport | Core, Wire | production app targets |

Mobile imports only Core, Wire, Client, Features, Design, Security, and Transport. Host owns Storage and MacPlatform composition.

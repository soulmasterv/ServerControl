# ServerControl

SwiftUI iOS 17 app with server statistics, PM2 and Docker controls, a Gemini placeholder, and Keychain token settings. GitHub Actions builds an unsigned IPA for SideStore. Never commit server tokens or Apple credentials.

API contract: GET /api/dashboard, GET /api/health, POST /api/process/{id}/{start|restart|stop}, POST /api/docker/{name}/{start|restart|stop}. Check the models against your existing backend before live use.

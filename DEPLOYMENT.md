# SSPACE — déploiement de production

## Site Web (Vercel)

Le dépôt de référence est **Sylvain496/sspace**, branche **main**. Le projet Vercel doit utiliser :

- Repository : `Sylvain496/sspace`
- Production Branch : `main`
- Root Directory : `.` (racine du dépôt)
- Framework Preset : `Other`
- Build Command : aucune commande de build
- Output Directory : `.`

Le site est une application HTML/CSS/JavaScript statique. Vercel doit publier directement les fichiers présents à la racine : `index.html`, `manifest.webmanifest`, `sw.js`, `messenger.html`, `modules.html`, ainsi que les dossiers `icons/` et `assets/`.

Quand l'intégration GitHub de Vercel est active, chaque mise à jour de `main` déclenche un nouveau déploiement de production. Ne configure pas Netlify en parallèle pour ce même site.

Après chaque déploiement, vérifier au minimum :
- `/` et `/index.html`
- `/messenger.html`
- `/modules.html`
- `/sw.js`
- `/manifest.webmanifest`

Le fichier `vercel.json` définit des en-têtes de revalidation pour les pages HTML, le manifeste et le service worker afin d'éviter qu'un ancien shell PWA reste affiché après une mise à jour.

## Application Android

- Le workflow GitHub Actions construit l'APK de débogage `app-debug.apk`.
- Le build synchronise les fichiers Web de la racine vers `android/app/src/main/assets` avant compilation.
- Télécharge l'artefact **SSPACE-Android-APK** dans l'exécution GitHub Actions.
- Pour une diffusion Play Store ou une installation de production signée, il faudra configurer une clé de signature Android privée. Elle ne doit jamais être ajoutée au dépôt.

## Base de données Supabase

Les migrations SQL du dossier `supabase/migrations` décrivent le schéma, les règles RLS, le stockage et les fonctions utilisées par SSPACE. Elles doivent être appliquées dans l'ordre chronologique sur le projet Supabase SSPACE.

Le frontend utilise uniquement une clé publique publishable. Ne copie jamais une clé secrète ou `service_role` dans le navigateur, l'application Android ou le dépôt.

## Contrôles après déploiement

- Crée deux comptes de test distincts.
- Vérifie les demandes d'amis, l'ouverture d'une conversation, l'indicateur de saisie, l'accusé « Vu » et le son de notification.
- Vérifie le formulaire de profil, la confidentialité des renseignements personnels et la modification de la bio.
- Teste le clavier, l'envoi de médias et les autorisations microphone/caméra sur un téléphone Android réel.

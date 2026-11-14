# SSPACE — paquet de déploiement

## Version Web (Netlify)
1. Décompresse `SSPACE-deploiement.zip`.
2. Dans Netlify, ouvre le site SSPACE ou crée un nouveau site.
3. Dépose le dossier racine extrait (celui qui contient `index.html`, `manifest.webmanifest` et `sw.js`) dans le déploiement manuel.
4. Attends la fin du déploiement et ouvre l'URL HTTPS du site.

Le fichier `index.html` contient déjà l'URL Supabase et la clé publishable publique du projet SSPACE. Aucune clé `service_role` n'est incluse dans le navigateur.

## Application Android
- Le workflow GitHub Actions construit l'APK de débogage `app-debug.apk`.
- Télécharge l'artefact **SSPACE-Android-APK** dans l'exécution GitHub Actions.
- Pour une diffusion Play Store ou une installation de production signée, il faudra configurer une clé de signature Android privée. Elle ne doit jamais être ajoutée au dépôt.

## Base de données Supabase
Les migrations SQL du dossier `supabase/migrations` décrivent le schéma, les règles RLS, le stockage et les fonctions utilisées par SSPACE. Elles ont déjà été appliquées au projet Supabase actuellement relié à SSPACE.

Si tu déploies sur un autre projet Supabase, configure d'abord son URL et sa clé publishable dans `index.html`, puis applique les migrations dans l'ordre chronologique depuis le SQL Editor de Supabase. Ne copie jamais une clé secrète ou `service_role` dans le code client.

## Contrôles après déploiement
- Crée deux comptes de test distincts.
- Vérifie les demandes d'amis, l'ouverture d'une conversation, l'indicateur de saisie, l'accusé « Vu » et le son de notification.
- Vérifie le formulaire de profil, la confidentialité des renseignements personnels et la modification de la bio.
- Teste le clavier et l'envoi de messages sur un téléphone Android réel.

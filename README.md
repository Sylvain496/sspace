# SSPACE

SSPACE est une plateforme sociale francophone axée sur les blogues, les textes et la communauté.

## Inclus dans cette version
- Inscription et connexion par courriel avec Supabase Auth
- Profils et biographies modifiables
- Fil d'actualité et publication de billets
- Commentaires et mentions J’aime persistants
- Découverte des membres et abonnements
- Interface responsive, installable comme application web (PWA)
- Projet Android natif WebView
- Workflow GitHub Actions pour compiler un APK Android debug

## Configuration Supabase
Le frontend utilise le projet Supabase SSPACE et une clé publique publishable. Il s'appuie sur les tables profiles, posts, comments, likes et follows, avec Row Level Security activée.

## Lancer le site
Publier le contenu du dépôt sur un hébergeur statique HTTPS (GitHub Pages, Cloudflare Pages ou équivalent). L'authentification et les fonctions sociales nécessitent Internet.

## Compiler Android
Dans GitHub, ouvrir Actions → Build Android APK → Run workflow. À la fin, télécharger l'artefact SSPACE-Android-APK. Le fichier produit est un APK debug installable pour les essais; une publication Play Store nécessitera une signature de production.

## À compléter avant lancement public
Cette version constitue le socle fonctionnel. Il reste à ajouter les tests utilisateurs, la modération et signalement, la récupération de mot de passe personnalisée, l'envoi de photos, les notifications, et les outils administrateur. Vérifier aussi les réglages d'URL de redirection et de confirmation courriel dans Supabase Auth.

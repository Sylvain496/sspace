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


## Centre des 12 modules
La page `modules.html` fournit un tableau de bord responsive des douze modules SSPACE, avec recherche, filtres, détails et état d'intégration. Elle distingue les fonctions déjà présentes, partielles et celles à développer. Elle ne remplace pas les intégrations backend encore nécessaires.


## Intégration du Centre et du Salon des connectés
- Le Centre des 12 modules est accessible depuis le menu principal et la navigation latérale.
- Le module Salon des connectés est relié au projet Supabase SSPACE : lecture des 50 derniers messages, envoi authentifié et abonnement Supabase Realtime sur `sspace_live_chat_messages`.
- Le salon exige une session SSPACE active. La table possède RLS activée, des règles de lecture pour les membres authentifiés et une règle d'insertion limitée à l'auteur connecté (500 caractères maximum).
- Le salon est livré en bêta : modération renforcée, tests multi-appareils et anti-abus restent à compléter.
- Le reste des modules doit être raccordé progressivement aux tables et fonctions existantes, après audit des politiques RLS. Aucune modification de schéma n'a été appliquée dans cette étape.


## Statistiques, musique, récompenses et boutique
- Les statistiques personnelles sont calculées côté serveur par `sspace_my_dashboard_stats()` : publications, abonnés, abonnements, visites de profil (somme des visites), J’aime et commentaires reçus.
- SSPACE Music utilise la table existante `sspace_music_tracks` et le bucket privé `sspace-community-media`. Les membres connectés peuvent téléverser un fichier audio (50 Mo maximum), écouter via URL signée et supprimer leurs propres morceaux. Les écoutes sont consignées une fois par morceau et par jour pour les défis.
- Les écoutes musicales sont protégées par RLS; chaque membre ne peut lire que son propre historique d'écoute. Les insertions sont réalisées par une fonction serveur et non par une écriture directe du navigateur.
- Les récompenses reposent sur `sspace_reward_ledger`, `sspace_badge_catalog`, `sspace_user_badges` et des RPC sécurisées. Le bonus quotidien vaut 5 points; un défi terminé donne 20 points, une fois par semaine. Les progressions sont recalculées à partir des publications, commentaires et écoutes réelles.
- La boutique charge le catalogue actif et l’accès Premium du membre. Le paiement demeure volontairement désactivé : le catalogue ne fournit pas de tarifs et aucun flux de paiement ni webhook n’est configuré.
- Migration : `supabase/migrations/20261126153000_sspace_stats_music_rewards_backend.sql`. Une correction du calcul des visites totales est également appliquée dans Supabase.
- Les fonctions backend exigent une session authentifiée; les tables de récompenses ne permettent pas aux clients d'écrire directement les points ou les badges.

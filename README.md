# DevReports — plateforme de rapports de développement

Une petite plateforme web responsive pour une équipe de développement de jeux vidéo.

## Fonctionnalités
- Connexion et création de compte par e-mail/mot de passe.
- Rôle développeur par défaut.
- Formulaire de rapport : projet, catégorie, version, titre, travaux réalisés, problèmes, prochaines étapes.
- Un développeur ne voit que ses rapports.
- Un administrateur voit les rapports de toute l'équipe et peut supprimer un rapport.
- Recherche dans les rapports.
- Interface sombre responsive.

## Important : authentification réelle
Le site utilise Supabase pour l'authentification et la base de données. Il ne faut pas remplacer cela par un simple mot de passe écrit dans le JavaScript : ce serait facilement contournable.

## Installation
1. Créez un projet sur https://supabase.com/.
2. Dans Supabase, ouvrez **SQL Editor** et exécutez tout le contenu de `supabase_setup.sql`.
3. Ouvrez **Project Settings > API** et copiez :
   - Project URL
   - la clé publique `anon` / `publishable` (jamais la clé `service_role`).
4. Dans `index.html`, remplacez `COLLEZ_ICI_URL_SUPABASE` et `COLLEZ_ICI_CLE_PUBLIQUE_SUPABASE` par l'URL du projet et sa clé publique `anon`/`publishable`. Cette clé publique est prévue pour le navigateur et reste protégée par les règles RLS. Ne mettez jamais la clé `service_role` dans le site.
5. Hébergez le dossier sur Netlify, GitHub Pages (si votre configuration autorise le chargement de scripts externes) ou un hébergeur statique.
6. Dans Supabase > Authentication > URL Configuration, renseignez l'URL de votre site.
7. Créez votre compte sur le site.
8. Dans Supabase > SQL Editor, exécutez la requête de promotion admin située à la fin de `supabase_setup.sql`, après avoir remplacé l'adresse e-mail.

Si vous avez déjà exécuté une ancienne version du SQL, relancez le script complet mis à jour pour remplacer les policies et éviter la récursion RLS.

## Gestion des accès
- Les inscriptions créent uniquement des comptes `developer`.
- Un développeur ne peut pas se donner le rôle admin depuis le site.
- Le rôle admin doit être attribué par une personne ayant accès au projet Supabase.
- Les règles RLS de Supabase protègent les données côté serveur.

## Personnalisation
Le nom DevReports, les couleurs et les textes peuvent être modifiés dans `index.html`.

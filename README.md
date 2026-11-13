# DevReports

Application statique d’équipe pour les rapports, les avertissements et le suivi des tâches, avec Supabase Auth et PostgreSQL/RLS.

## Fonctionnalités

- Comptes développeurs soumis à validation et rôles administrateur protégés côté serveur.
- Rapports d’avancement, modération et gestion Discord, recherche et export PDF A4.
- Avertissements modifiables/supprimables par les admins et contestables par le membre concerné.
- Tableau Kanban partagé : tâches à planifier, à faire, en cours, à vérifier et terminées.
- Attribution, échéances, priorités, étiquettes, checklist et commentaires sur les tâches.
- Demandes d’absence avec validation admin et signalements de retard suivis dans l’espace équipe.
- Messagerie générale intégrée pour les membres actifs, avec actualisation en direct et repli périodique.
- Rôles personnalisés avec attribution multiple, et édition sécurisée du nom, pseudo, e-mail et mot de passe des comptes.
- Envoi d’un lien Supabase de réinitialisation de mot de passe; aucun mot de passe temporaire n’est transmis par e-mail.
- Gestion des projets, interface responsive en thème clair/sombre et export JSON des données accessibles.

## Configuration et publication

1. Dans Supabase, ouvre **SQL Editor** et exécute le script complet `supabase_setup.sql`. Il peut être relancé pour appliquer les évolutions du schéma et recréer les politiques RLS.
2. Vérifie `SUPABASE_URL` et `SUPABASE_ANON_KEY` au début de `app.js`. Seule la clé publique `publishable`/`anon` est prévue dans le navigateur. **Ne place jamais une clé `secret` ou `service_role` dans le dépôt.**
3. Publie les fichiers `index.html`, `app.js`, `styles.css` et `supabase_setup.sql` sur GitHub Pages ou un hébergeur statique.
4. Dans **Supabase → Authentication → URL Configuration**, ajoute l’URL publiée et configure la confirmation e-mail/CAPTCHA selon les besoins du studio.
   Ajoute aussi `https://wolfiii-ytb.github.io/DevReports/` à **Redirect URLs** pour que les liens de réinitialisation reviennent vers le site.
5. Crée le compte admin et attribue le rôle depuis Supabase avec accès SQL, jamais depuis le formulaire public. La requête modèle est commentée à la fin du script SQL.

### Fonction sécurisée d’administration des comptes

Le changement d’e-mail et de mot de passe passe par `supabase/functions/admin-manage-user/index.ts`. La passerelle vérifie le JWT; la fonction revalide la session et confirme le rôle admin côté serveur avant d’utiliser l’API Admin Auth. La fonction prend en charge les variables Supabase de clés secrètes/publiables actuelles et leurs équivalents historiques. La clé secrète n’est jamais dans le site ni le dépôt.

1. Installe/ouvre Supabase CLI, puis lance `supabase login` et `supabase link --project-ref bylwvlxxvgumvqgpwgod` depuis le dépôt.
2. Dans Supabase **Settings → API**, copie l’origine publique du site (par ex. `https://<compte>.github.io`, sans `/DevReports/`) et configure-la : `supabase secrets set ALLOWED_ORIGINS=https://<compte>.github.io`.
3. Déploie la fonction : `supabase functions deploy admin-manage-user`.

Les environnements Supabase injectent les clés de projet à l’exécution. Ne saisis et ne copie jamais une clé secrète dans `app.js`, un dépôt, une capture d’écran ou un message. Si l’adresse e-mail change, Supabase peut demander sa confirmation par e-mail selon les réglages Auth.

Si le script SQL a déjà été exécuté auparavant, relance sa dernière version complète. Les développeurs actifs peuvent voir les profils actifs (identifiant et nom uniquement dans les requêtes de l’application), les tâches de l’équipe et leurs commentaires. Seuls les admins peuvent gérer les comptes, les projets et les vues d’administration. La clé publique ne protège pas les données à elle seule : les politiques RLS sont indispensables.

## Sauvegardes

Le bouton **Télécharger l’export JSON** dans **Projets** télécharge une copie des lignes accessibles pour les rapports, tâches, commentaires, profils, rôles, projets, avertissements, sanctions, absences, retards, messages et contestations. Ce fichier est une copie de données, pas un mécanisme de restauration automatique : garde-le dans un endroit privé et utilise aussi les sauvegardes/exports proposés par Supabase pour pouvoir restaurer la base et les comptes d’authentification.

## Fichiers

- `index.html` : structure des pages et formulaires.
- `app.js` : authentification et logique de l’application.
- `styles.css` : mise en page responsive et thèmes.
- `supabase_setup.sql` : tables, fonctions, index et politiques RLS.
- `supabase/functions/admin-manage-user/index.ts` : API serveur admin pour les opérations Auth sensibles.

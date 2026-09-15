-- =====================================================================
--  Migration 2 — accès réservé aux personnes invitées
--  À coller dans SQL Editor (nouvel onglet) puis Run. Rejouable.
-- =====================================================================

-- Un utilisateur invité ne peut pas lire la table invitations (elle est
-- réservée aux administrateurs). Cette fonction lui permet quand même de
-- rejoindre l'organisation, en vérifiant elle-même que l'invitation existe,
-- correspond bien à SON adresse email, n'est ni expirée ni déjà utilisée.
create or replace function rejoindre_par_invitation()
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare inv invitations; mail text;
begin
  mail := lower(coalesce(auth.jwt() ->> 'email', ''));
  if mail = '' then return null; end if;

  select * into inv from invitations
   where lower(email) = mail
     and accepte_le is null
     and expire_le > now()
   order by cree_le desc
   limit 1;

  if inv is null then return null; end if;

  insert into membres (organisation_id, profil_id, role)
  values (inv.organisation_id, auth.uid(), inv.role)
  on conflict (organisation_id, profil_id) do nothing;

  update invitations set accepte_le = now() where id = inv.id;
  return inv.organisation_id;
end $$;

-- La création d'une organisation est réservée au propriétaire du projet.
-- Toute autre personne doit passer par une invitation.
create or replace function creer_organisation(p_nom text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare org uuid; mail text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  mail := lower(coalesce(auth.jwt() ->> 'email', ''));

  -- ⚠️ Remplace cette adresse si tu changes de compte principal.
  if mail <> 'elreusisley@gmail.com' then
    raise exception 'Accès refusé : demande une invitation.';
  end if;

  select organisation_id into org from membres where profil_id = auth.uid() limit 1;
  if org is not null then return org; end if;

  insert into organisations (nom) values (p_nom) returning id into org;
  insert into membres (organisation_id, profil_id, role) values (org, auth.uid(), 'admin');
  return org;
end $$;

select 'migration 2 ok' as resultat;

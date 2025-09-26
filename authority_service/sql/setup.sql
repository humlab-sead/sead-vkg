/*
create extension if not exists unaccent;
create extension if not exists pg_trgm;
create extension if not exists postgis;

create schema if not exists authority;
*/
-- Immutable wrapper around unaccent using a fixed dictionary
create or replace function authority.immutable_unaccent(p_value text)
returns text language sql immutable parallel safe
as $$
  select unaccent('public.unaccent'::regdictionary, p_value)
$$;

drop view if exists authority.sites;
create or replace view authority.sites as
  select  site_id,
          site_name as label,
          authority.immutable_unaccent(lower(site_name)) as norm_label,
          latitude_dd,
          longitude_dd,
          national_site_identifier,
          site_description,
          st_setsrid(st_makepoint(longitude_dd, latitude_dd), 4326) as geom
  from public.tbl_sites;

create index if not exists tbl_sites_norm_trgm
on public.tbl_sites
using gin ( (authority.immutable_unaccent(lower(site_name))) gin_trgm_ops );


drop function if exists authority.fuzzy_sites(text, integer);
create or replace function authority.fuzzy_sites(p_text text, p_limit integer default 10)
returns table ( site_id integer, label text, name_sim double precision )
language sql
stable
as $$
    with params as (
        select unaccent(lower(p_text))::text as q
    )
        select
        s.site_id,
        s.label,
        greatest(
            case when s.norm_label = (select q from params) then 1.0
                else similarity(s.norm_label, (select q from params))
            end, 0.0001
        ) as name_sim
        from authority.sites as s
        where s.norm_label % (select q from params)       -- trigram candidate filter
        order by name_sim desc, s.label
        limit p_limit;
$$;

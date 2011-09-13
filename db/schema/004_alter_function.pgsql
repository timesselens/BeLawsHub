begin;

    create or replace view _staatsblad_fr_docuid_per_cat as 
    select count(*),lower(m[1]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid,
                regexp_matches(title,$_$^(?:\d+ [a-z]+ \d+)?[\.\-\s\[\(]*(\w+\s?\w+)\s+(?:modifiant|du|de)$_$,'i') as m
            from staatsblad_fr 
            order by docuid) as foo 
    group by lower(m[1]) order by count desc;

    create or replace view _staatsblad_fr_named as 
    select count(*),lower(m[1]) as named, lower(m[2]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from
        (select id,
                docuid,
                regexp_matches(title,$_$((loi|decret))$_$,'i') as m
            from staatsblad_fr order by docuid) as foo 
    group by named,cat order by cat,count desc,named;

    create or replace view _staatsblad_fr_docuid_per_geo as 
    select count(*),lower(m[1]) as geo,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid, 
                regexp_matches(title,$_$(\w{4,}\s*(?:gewest|regering|gemeenschap))$_$,'i') as m 
            from staatsblad_fr order by docuid) as foo 
    group by geo order by count desc;

    create or replace function rehash_staatsblad_fr_cat_person_scope() returns void as $$
        begin
            drop table if exists __staatsblad_fr;
            create table __staatsblad_fr as
            select id,docuid,docdate,title,pretty,source,pdf_link,
                   (select cat from __staatsblad_fr_docuid_per_cat where docuid = any(docuids)) as cat, 
                   array((select name from person where docuid = any(staatsblad_fr_docuids))) as person, 
                   (select geo from _staatsblad_fr_docuid_per_geo g where docuid = any(docuids)) as scope 
            from staatsblad_fr;
            create unique index __staatsblad_fr_docuid_key on __staatsblad_fr using btree(docuid);
            create unique index __staatsblad_fr_id_key on __staatsblad_fr using btree(id);
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_fr_cat_person_scope() returns void as $$
        begin
            drop table if exists __staatsblad_fr;
            create table __staatsblad_fr as
            select id,docuid,docdate,title,pretty,source,pdf_link,
                   (select cat from __staatsblad_fr_docuid_per_cat where docuid = any(docuids)) as cat, 
                   array((select name from person where docuid = any(staatsblad_fr_docuids))) as person, 
                   (select geo from _staatsblad_fr_docuid_per_geo g where docuid = any(docuids)) as scope 
            from staatsblad_fr;
            create unique index __staatsblad_fr_docuid_key on __staatsblad_fr using btree(docuid);
            create unique index __staatsblad_fr_id_key on __staatsblad_fr using btree(id);
        end;
    $$ language plpgsql;

end;

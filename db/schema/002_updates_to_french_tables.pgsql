begin;

    drop table staatsblad_fr;
    create table staatsblad_fr (
        id serial primary key,
        ts timestamp default now(),
        docuid varchar(15) unique,
        docdate date,
        kind varchar(255),
        title text,
        body text,
        plain text,
        fts tsvector,
        markup text,
        pubid varchar(15),
        pubdate date,
        source varchar(255),
        pages integer,
        pdf_link text,
        pdf_page integer,
        effective varchar(12)
    );

    -- create text search configuration public.belaws_fr ( copy = pg_catalog.french );

    -- create text search dictionary belaws_nl_syn (TEMPLATE = synonym, SYNONYMS = belaws_nl_syn );

    -- create text search dictionary french_ispell( TEMPLATE = ispell, DictFile = french, AffFile = french, StopWords = french);
    -- create text search dictionary french_stem ( TEMPLATE = snowball, Language = french, StopWords = french );

    alter text search configuration belaws_fr alter mapping for asciiword, asciihword, hword_asciipart, word, hword, hword_part WITH french_ispell, french_stem;
    --alter text search configuration belaws_fr drop mapping for url, url_path, sfloat, float;


    create or replace function generate_tsvector_fr() returns trigger as $$
    begin
      new.fts :=
         setweight(to_tsvector('public.belaws_fr', coalesce(new.source,'')), 'A') ||
         setweight(to_tsvector('public.belaws_fr', coalesce(new.title,'')), 'A') ||
         setweight(to_tsvector('public.belaws_fr', coalesce(new.plain,'')), 'D');
      return new;
    end
    $$ language plpgsql;

    create trigger ftsupdate before insert or update on staatsblad_fr
        for each row execute procedure generate_tsvector_fr();

    create index staatsblad_fr_title_fts on staatsblad_fr using gin(to_tsvector('public.belaws_fr',title));
    create index staatsblad_fr_plain_fts on staatsblad_fr using gin(to_tsvector('public.belaws_fr',plain));

    CREATE TABLE staatsblad_status_fr (id serial primary key, ts timestamp default now(), docuid varchar(15), status varchar(20));

    create or replace view _staatsblad_fr_docuid_per_cat as 
    select count(*),lower(m[1]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid,
                regexp_matches(title,$_$^(?:\d+ [a-z]+ \d+)?[\.\-\s\[\(]*([a-z]+\s?[a-z]+)\s+(?:tot|houdende|ter|waarbij|betreffende|van|genomen|getroffen|met|dat|inzake|op|voor|over|waarmee|tussen|tegen|nopens)$_$,'i') as m
            from staatsblad_fr 
            order by docuid) as foo 
    group by lower(m[1]) order by count desc;

    create or replace view _staatsblad_fr_named as 
    select count(*),lower(m[1]) as named, lower(m[2]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from
        (select id,
                docuid,
                regexp_matches(title,$_$([^\s\d\.\[\(\,]{4,}\ *\w*(wet|decreet|besluit|programma|boek))$_$,'i') as m
            from staatsblad_fr order by docuid) as foo 
    group by named,cat order by cat,count desc,named;

    create or replace view _staatsblad_fr_docuid_per_geo as 
    select count(*),lower(m[1]) as geo,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid, 
                regexp_matches(title,$_$(\w{4,}\s*(?:gewest|regering|gemeenschap))$_$,'i') as m 
            from staatsblad_fr order by docuid) as foo 
    group by geo order by count desc;

    create or replace view _staatsblad_fr_docuid_per_source as 
        select count(*),
                trim(source) as source,
                array_agg(id) as ids, 
                array_agg(docuid) as docuids
        from staatsblad_fr where source <> '' group by trim(source) having count(*) > 1 order by count desc;

    create or replace function rehash_all() returns void as $$
        begin
            execute rehash_all_nl();
            execute rehash_all_fr();
        end;
    $$ language plpgsql;

    create or replace function rehash_all_nl() returns void as $$
        begin
            execute rehash_staatsblad_nl_docuid_per_cat();
            execute rehash_staatsblad_nl_docuid_per_geo();
            execute rehash_staatsblad_nl_docuids_in_body();
            execute rehash_staatsblad_nl_cat_person_scope();
        end;
    $$ language plpgsql;

    create or replace function rehash_all_fr() returns void as $$
        begin
            execute rehash_staatsblad_fr_docuid_per_cat();
            execute rehash_staatsblad_fr_docuid_per_geo();
            execute rehash_staatsblad_fr_docuids_in_body();
            execute rehash_staatsblad_fr_cat_person_scope();
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_fr_cat_person_scope() returns void as $$
        begin
            drop table if exists __staatsblad_fr;
            create table __staatsblad_fr as
            select id,docuid,docdate,title,markup,source,pdf_link,
                   (select cat from __staatsblad_fr_docuid_per_cat where docuid = any(docuids)) as cat, 
                   array((select name from person where docuid = any(staatsblad_fr_docuids))) as person, 
                   (select geo from _staatsblad_fr_docuid_per_geo g where docuid = any(docuids)) as scope 
            from staatsblad_fr;
            create unique index __staatsblad_fr_docuid_key on __staatsblad_fr using btree(docuid);
            create unique index __staatsblad_fr_id_key on __staatsblad_fr using btree(id);
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_fr_docuids_in_body() returns void as $$
        begin
            drop table if exists __staatsblad_fr_docuid_in_body;
            create table __staatsblad_fr_docuid_in_body as
                select docuid[1],count(*) from 
                    (select regexp_matches(body,$_$\d{4}-\d{2}-\d{2}\/\d{2}$_$,'g') as docuid from staatsblad_fr) as foo 
                group by docuid[1] order by count desc;
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_fr_docuid_per_cat() returns void as $$
        begin
            drop table if exists __staatsblad_fr_docuid_per_cat;
            create table __staatsblad_fr_docuid_per_cat as
                select * from _staatsblad_fr_docuid_per_cat;
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_fr_docuid_per_geo() returns void as $$
        begin
            drop table if exists __staatsblad_fr_docuid_per_geo;
            create table __staatsblad_fr_docuid_per_geo as
                select * from _staatsblad_fr_docuid_per_geo;
        end;
    $$ language plpgsql;

    create view _series_date_staatsblad_fr as                                                                                                      
        select foo.min + (generate_series(0,((((foo.max - foo.min) / 365 ) + 1 ) * 12)) || ' month')::interval as date from (select min(docdate),max(docdate) from staatsblad_fr) as foo;

    --------------------------------------------------------------------------------------------------------------

    drop table person cascade;
    create table person (id serial, ts timestamp default now(), name varchar(50) unique not null, party varchar(255), staatsblad_nl_ids integer[], staatsblad_nl_docuids varchar[], staatsblad_fr_ids integer[], staatsblad_fr_docuids varchar[]);

    insert into person (name) values 
            ('A. ANTOINE'), 
            ('A. BOURGEOIS'), 
            ('A. DUQUESNE'), 
            ('A. FLAHAUT'), 
            ('A. TURTELBOOM'), 
            ('B. ANCIAUX'), 
            ('B. CEREXHE'), 
            ('B. CLERFAYT'), 
            ('B. GENTGES'), 
            ('B. GROUWELS'), 
            ('B. LUTGEN'), 
            ('B. SOMERS'), 
            ('B. TOBBACK'), 
            ('C. DUPONT'), 
            ('C. FONCK'), 
            ('C. PICQUE'), 
            ('D. DONFUT'), 
            ('D. REYNDERS'), 
            ('D. SIMONET'), 
            ('E. DERYCKE'), 
            ('E. HUYTEBROECK'), 
            ('E. SCHOUPPE'), 
            ('E. TILLIEUX'), 
            ('F. LAANAN'), 
            ('F. VAN DEN BOSSCHE'), 
            ('F. VANDENBROUCKE'), 
            ('G. BOURGEOIS'), 
            ('G. PERL'), 
            ('G. VANHENGEL'), 
            ('G. VERHOFSTADT'), 
            ('H. CREVITS'), 
            ('H. LAMBERTZ'), 
            ('I. DURANT'), 
            ('I. LIETEN'), 
            ('I. VERVOTTE'), 
            ('J. CHABERT'), 
            ('J.-C. MARCOURT'), 
            ('J. HAPPART'), 
            ('J. MILQUET'), 
            ('J.-M. NOLLET'), 
            ('J. PEETERS'), 
            ('J. PIETTE'), 
            ('J. SANTKIN'), 
            ('J. SCHAUVLIEGE'), 
            ('J. SIMONET'), 
            ('J. VANDE LANOTTE'),
            ('J. VANDEURZEN'), 
            ('J. VISEUR'), 
            ('K. PEETERS'), 
            ('K. PINXTEN'), 
            ('L. DEHAENE'), 
            ('L. MICHEL'), 
            ('L. ONKELINX'), 
            ('L. TOBBACK'), 
            ('L. VANRAES'), 
            ('M. AELVOET'), 
            ('M. ARENA'), 
            ('M. COLLA'), 
            ('M. DAERDEN'), 
            ('M. KEULEN'), 
            ('M. NOLLET'), 
            ('M. SMET'), 
            ('M. VERWILGHEN'), 
            ('M. WATHELET'), 
            ('N. BIJLAGE'), 
            ('O. PAASCH'), 
            ('P. CEYSENS'), 
            ('P. DE CREM'), 
            ('P. DEWAEL'), 
            ('P. FURLAN'), 
            ('Ph. HENRY'), 
            ('Ph. MUYTERS'), 
            ('P. MAGNETTE'), 
            ('P. MUYTERS'), 
            ('P. SMET'), 
            ('R. COLLIGNON'), 
            ('R. DAEMS'), 
            ('R. DEMOTTE'), 
            ('S. DECLERCK'), 
            ('S. LARUELLE'), 
            ('S. VANACKERE'), 
            ('V. HEEREN'), 
            ('V. VAN QUICKENBORNE'), 
            ('Y. LETERME');



    create or replace function person_process() returns trigger as $$
        declare
            ids_nl integer[];
            docuids_nl varchar[];
            ids_fr integer[];
            docuids_fr varchar[];
        begin
            select array_agg(id) into ids_nl from staatsblad_nl where plain ~ NEW.name;
            select array_agg(docuid) into docuids_nl from staatsblad_nl where plain ~ NEW.name;
            select array_agg(id) into ids_fr from staatsblad_fr where plain ~ NEW.name;
            select array_agg(docuid) into docuids_fr from staatsblad_fr where plain ~ NEW.name;
            NEW.staatsblad_nl_ids = ids_nl;
            NEW.staatsblad_nl_docuids = docuids_nl;
            NEW.staatsblad_fr_ids = ids_fr;
            NEW.staatsblad_fr_docuids = docuids_fr;
            return NEW;
        end
    $$ language plpgsql;

    create trigger person_process before insert or update on person
        for each row execute procedure person_process();

    create or replace view _person_per_party as select id,name,party from person order by party,name;

    create view _person_cosign_link as 
        select p1.name as source, p2.name as target, 
                coalesce(array_upper(array(select unnest(p1.staatsblad_nl_docuids) intersect select unnest(p2.staatsblad_nl_docuids)),1),0) as value 
        from person p1, person p2 where p1.name != p2.name;

    ---------------------------------------------------------------------------------------------------------------------------------
    create or replace function words_process() returns trigger as $$
        declare
            ids_nl integer[];
            docuids_nl varchar[];
            ids_fr integer[];
            docuids_fr varchar[];
        begin
            select array_agg(id) into ids_nl from staatsblad_nl where plain ~ NEW.words;
            select array_agg(docuid) into docuids_nl from staatsblad_nl where plain ~ NEW.words;
            select array_agg(id) into ids_fr from staatsblad_fr where plain ~ NEW.words;
            select array_agg(docuid) into docuids_fr from staatsblad_fr where plain ~ NEW.words;
            NEW.staatsblad_nl_ids = ids_nl;
            NEW.staatsblad_nl_docuids = docuids_nl;
            NEW.staatsblad_fr_ids = ids_fr;
            NEW.staatsblad_fr_docuids = docuids_fr;
            return NEW;
        end
    $$ language plpgsql;

    drop table words cascade;
    create table words (id serial, ts timestamp default now(), words varchar(255), staatsblad_nl_ids integer[], staatsblad_nl_docuids varchar[], staatsblad_fr_ids integer[], staatsblad_fr_docuids varchar[]);

    create trigger words_process before insert or update on words
        for each row execute procedure words_process();

    create view _word_trends_per_month as select words,count(*),date_trunc('month',docdate) as month from 
        (select * from (select words,unnest(staatsblad_nl_docuids) as docuid from words) as foo, staatsblad_nl b where foo.docuid = b.docuid) as fnord 
    group by words,date_trunc('month',docdate) order by month;

    --------------------------------------------------------------------------------------------------------------

commit;

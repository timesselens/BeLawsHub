begin;

    create table staatsblad_nl (
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

    create text search configuration public.belaws_nl ( copy = pg_catalog.dutch );

    -- create text search dictionary belaws_nl_syn (TEMPLATE = synonym, SYNONYMS = belaws_nl_syn );

    create text search dictionary dutch_ispell( TEMPLATE = ispell, DictFile = dutch, AffFile = dutch, StopWords = dutch);
    create text search dictionary dutch_stem ( TEMPLATE = snowball, Language = dutch, StopWords = dutch );

    alter text search configuration belaws_nl alter mapping for asciiword, asciihword, hword_asciipart, word, hword, hword_part WITH dutch_ispell, dutch_stem;
    alter text search configuration belaws_nl drop mapping for email, url, url_path, sfloat, float;


    create or replace function generate_tsvector() returns trigger as $$
    begin
      new.fts :=
         setweight(to_tsvector('public.belaws_nl', coalesce(new.source,'')), 'A') ||
         setweight(to_tsvector('public.belaws_nl', coalesce(new.title,'')), 'A') ||
         setweight(to_tsvector('public.belaws_nl', coalesce(new.plain,'')), 'D');
      return new;
    end
    $$ language plpgsql;

    create trigger ftsupdate before insert or update on staatsblad_nl
        for each row execute procedure generate_tsvector();

    create index staatsblad_nl_title_fts on staatsblad_nl using gin(to_tsvector('public.belaws_nl',title));
    create index staatsblad_nl_plain_fts on staatsblad_nl using gin(to_tsvector('public.belaws_nl',plain));

    CREATE TABLE staatsblad_status_nl (id serial primary key, ts timestamp default now(), docuid varchar(15), status varchar(20));

    create or replace view _staatsblad_nl_docuid_per_cat as 
    select count(*),lower(m[1]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid,
                regexp_matches(title,$_$^(?:\d+ [a-z]+ \d+)?[\.\-\s\[\(]*([a-z]+\s?[a-z]+)\s+(?:tot|houdende|ter|waarbij|betreffende|van|genomen|getroffen|met|dat|inzake|op|voor|over|waarmee|tussen|tegen|nopens)$_$,'i') as m
            from staatsblad_nl 
            order by docuid) as foo 
    group by lower(m[1]) order by count desc;

    create or replace view _staatsblad_nl_named as 
    select count(*),lower(m[1]) as named, lower(m[2]) as cat,array_agg(id) as ids,array_agg(docuid) as docuids from
        (select id,
                docuid,
                regexp_matches(title,$_$([^\s\d\.\[\(\,]{4,}\ *\w*(wet|decreet|besluit|programma|boek))$_$,'i') as m
            from staatsblad_nl order by docuid) as foo 
    group by named,cat order by cat,count desc,named;

    create or replace view _staatsblad_nl_docuid_per_geo as 
    select count(*),lower(m[1]) as geo,array_agg(id) as ids,array_agg(docuid) as docuids from 
        (select id,
                docuid, 
                regexp_matches(title,$_$(\w{4,}\s*(?:gewest|regering|gemeenschap))$_$,'i') as m 
            from staatsblad_nl order by docuid) as foo 
    group by geo order by count desc;

    create or replace view _staatsblad_nl_docuid_per_source as 
        select count(*),
                trim(source) as source,
                array_agg(id) as ids, 
                array_agg(docuid) as docuids
        from staatsblad_nl where source <> '' group by trim(source) having count(*) > 1 order by count desc;

    --create language plpgsql;

    create or replace function rehash_all() returns void as $$
        begin
            execute rehash_staatsblad_nl_docuid_per_cat();
            execute rehash_staatsblad_nl_docuid_per_geo();
            execute rehash_staatsblad_nl_docuids_in_body();
            execute rehash_staatsblad_nl_cat_person_scope();
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_nl_cat_person_scope() returns void as $$
        begin
            drop table if exists __staatsblad_nl;
            create table __staatsblad_nl as
            select id,docuid,docdate,title,markup,source,pdf_link,
                   (select cat from __staatsblad_nl_docuid_per_cat where docuid = any(docuids)) as cat, 
                   array((select name from person where docuid = any(staatsblad_nl_docuids))) as person, 
                   (select geo from _staatsblad_nl_docuid_per_geo g where docuid = any(docuids)) as scope 
            from staatsblad_nl;
            create unique index __staatsblad_nl_docuid_key on __staatsblad_nl using btree(docuid);
            create unique index __staatsblad_nl_id_key on __staatsblad_nl using btree(id);
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_nl_docuids_in_body() returns void as $$
        begin
            drop table if exists __staatsblad_nl_docuid_in_body;
            create table __staatsblad_nl_docuid_in_body as
                select docuid[1],count(*) from 
                    (select regexp_matches(body,$_$\d{4}-\d{2}-\d{2}\/\d{2}$_$,'g') as docuid from staatsblad_nl) as foo 
                group by docuid[1] order by count desc;
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_nl_docuid_per_cat() returns void as $$
        begin
            drop table if exists __staatsblad_nl_docuid_per_cat;
            create table __staatsblad_nl_docuid_per_cat as
                select * from _staatsblad_nl_docuid_per_cat;
        end;
    $$ language plpgsql;

    create or replace function rehash_staatsblad_nl_docuid_per_geo() returns void as $$
        begin
            drop table if exists __staatsblad_nl_docuid_per_geo;
            create table __staatsblad_nl_docuid_per_geo as
                select * from _staatsblad_nl_docuid_per_geo;
        end;
    $$ language plpgsql;

    create view _series_date_staatsblad_nl as                                                                                                      
        select foo.min + (generate_series(0,((((foo.max - foo.min) / 365 ) + 1 ) * 12)) || ' month')::interval as date from (select min(docdate),max(docdate) from staatsblad_nl) as foo;

    --------------------------------------------------------------------------------------------------------------

    create table person (id serial, ts timestamp default now(), name varchar(50) unique not null, party varchar(255), staatsblad_nl_ids integer[], staatsblad_nl_docuids varchar[]);

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
        begin
            select array_agg(id) into ids_nl from staatsblad_nl where plain ~ NEW.name;
            select array_agg(docuid) into docuids_nl from staatsblad_nl where plain ~ NEW.name;
            NEW.staatsblad_nl_ids = ids_nl;
            NEW.staatsblad_nl_docuids = docuids_nl;
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
        begin
            select array_agg(id) into ids_nl from staatsblad_nl where plain ~ NEW.words;
            select array_agg(docuid) into docuids_nl from staatsblad_nl where plain ~ NEW.words;
            NEW.staatsblad_nl_ids = ids_nl;
            NEW.staatsblad_nl_docuids = docuids_nl;
            return NEW;
        end
    $$ language plpgsql;

    create table words (id serial, ts timestamp default now(), words varchar(255), staatsblad_nl_ids integer[], staatsblad_nl_docuids varchar[]);

    create trigger words_process before insert or update on words
        for each row execute procedure words_process();


    create view _word_trends_per_month as select words,count(*),date_trunc('month',docdate) as month from 
        (select * from (select words,unnest(staatsblad_nl_docuids) as docuid from words) as foo, staatsblad_nl b where foo.docuid = b.docuid) as fnord 
    group by words,date_trunc('month',docdate) order by month;



    --select * from
    --    _series_date_staatsblad_nl d,
    --    (select * from (select words,unnest(staatsblad_nl_docuids) as docuid from words) as foo, staatsblad_nl b where foo.docuid = b.docuid) as fnord 
    -- group by d, words,docdate order by docdate;


    --------------------------------------------------------------------------------------------------------------

    create table incoming (
        id serial primary key, 
        ts timestamp default now(), 
        parser varchar(255) not null, 
        lang varchar(4) not null, 
        uid varchar(255) not null, 
        body text not null
    );
    
    create index parser_lang_uid on incoming using btree(parser,lang,uid);

    create view _incoming as select id,ts,parser,lang,uid,length(body) from incoming;
    create view _incoming_latest as select max(id) as id,max(ts) as ts,parser,lang,uid,body from incoming group by parser,lang,uid,body;

    create table x_process_log (id serial primary key, ts timestamp default now(), iid integer, status varchar(20), uid varchar(255), old_val text, new_val text);

    create or replace function incoming_process() returns trigger as $$
        declare
            last_body text;
        begin
            if ( TG_OP = 'INSERT' ) then
                select body into last_body from incoming where parser = NEW.parser and lang = NEW.lang and uid=NEW.uid order by id desc limit 1;
                if ( last_body = NEW.body ) then
                    raise exception 'tried to insert same body as previous one for uid %, discarting', NEW.uid;
                    return NULL;
                else 
                    insert into x_process_log (iid, status, uid, old_val, new_val) values (NEW.id, 'new', NEW.uid, last_body, NEW.body);
                    return NEW;
                end if;
            end if;
            return NEW;
        end;
    $$ language plpgsql;

    create language plperlu;

    create or replace function diff(text,text) returns text as $$
        use Text::Diff;
        return diff(\$_[0], \$_[1]);
    $$ language plperlu;

    create or replace function diff_table(text,text) returns text as $$
        use Text::Diff;
        return diff(\$_[0], \$_[1], { STYLE => "Table" });
    $$ language plperlu;

    create trigger incoming_process before insert or update on incoming
        for each row execute procedure incoming_process();

    CREATE TABLE categorizer_words_nl (id serial, words varchar(255));
    create index categorizer_words_nl_fts on categorizer_words_nl using gin(to_tsvector('public.belaws_nl',words));


    --------------------------------------------------------------------------------------------------------------
    create table staatsblad_fr (
        id serial primary key,
        docuid varchar(15) unique,
        title text,
        body text,
        plain text,
        pubid varchar(15),
        pubdate date,
        source varchar(255),
        pages integer,
        pdf_href varchar(255),
        effective varchar(12)
    );

    create text search configuration public.belaws_fr ( copy = pg_catalog.french );

    -- create text search dictionary belaws_fr_syn (TEMPLATE = synonym, SYNONYMS = belaws_fr_syn );

    create text search dictionary french_ispell( TEMPLATE = ispell, DictFile = french, AffFile = french, StopWords = french);
    create text search dictionary french_stem ( TEMPLATE = snowball, Language = french, StopWords = french );

    alter text search configuration belaws_fr alter mapping for asciiword, asciihword, hword_asciipart, word, hword, hword_part WITH french_ispell, french_stem;
    alter text search configuration belaws_fr drop mapping for email, url, url_path, sfloat, float;

    create index staatsblad_fr_title_fts on staatsblad_fr using gin(to_tsvector('public.belaws_fr',title));
    create index staatsblad_fr_plain_fts on staatsblad_fr using gin(to_tsvector('public.belaws_fr',plain));

commit;

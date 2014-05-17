begin transaction;
    create or replace function rehash_staatsblad_nl_cat_person_scope() returns void as $$
        begin
            drop table if exists __staatsblad_nl;
            create table __staatsblad_nl as
            select id,docuid,docdate,title,pretty,source,pdf_link,
                   (select cat from __staatsblad_nl_docuid_per_cat where docuid = any(docuids)) as cat, 
                   array((select name from person where docuid = any(staatsblad_nl_docuids))) as person, 
                   (select geo from _staatsblad_nl_docuid_per_geo g where docuid = any(docuids)) as scope 
            from staatsblad_nl;
            create unique index __staatsblad_nl_docuid_key on __staatsblad_nl using btree(docuid);
            create unique index __staatsblad_nl_id_key on __staatsblad_nl using btree(id);
        end;
    $$ language plpgsql;
commit;

begin;

drop view _word_trends_per_month;

alter table staatsblad_nl add column pretty text;
alter table staatsblad_fr add column pretty text;

alter table staatsblad_nl drop column markup;
alter table staatsblad_fr drop column markup;

    create view _word_trends_per_month as select words,count(*),date_trunc('month',docdate) as month from 
        (select * from (select words,unnest(staatsblad_nl_docuids) as docuid from words) as foo, staatsblad_nl b where foo.docuid = b.docuid) as fnord 
    group by words,date_trunc('month',docdate) order by month;

end;

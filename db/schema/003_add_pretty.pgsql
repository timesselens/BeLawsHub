begin;

alter table staatsblad_nl add column pretty text;
alter table staatsblad_fr add column pretty text;

alter table staatsblad_nl drop column markup;
alter table staatsblad_fr drop column markup;

end;

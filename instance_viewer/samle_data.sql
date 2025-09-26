select DISTINCT ON (master_name, method_name, record_type_name, data_type_name)
	format('%s - %s - %s - %s', master_name, method_name, record_type_name, data_type_name), physical_sample_id
from tbl_data_types t
join tbl_datasets d using (data_type_id)
join (
	select 	master_set_id, 
			case when master_name like '%Bugs' then 'Bugs'
			     when master_name like '%MAL%' then 'MAL'
			     when master_name like '%DNA%' then 'aDNA'
			     when master_name like '%Dendrochronology%' then 'Dendrochronology'
			     when master_name like '%Ceramic%' then 'Ceramic'
			else master_name end as master_name
	from tbl_dataset_masters m
) m using (master_set_id)
join tbl_analysis_entities ae using (dataset_id)
join tbl_physical_samples ps using (physical_sample_id)
-- join tbl_sample_groups sg using (sample_group_id)
-- join tbl_sites s using (site_id)
join tbl_methods using (method_id)
join tbl_record_types using (record_type_id)
order by master_name, method_name, record_type_name, data_type_name, random();

with column_comments as (
	select
	  n.nspname        as schema,
	  c.relname        as table_name,
	  a.attname        as column_name,
	  d.description    as comment,
	  'column'         as object_type
	from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	join pg_attribute a on a.attrelid = c.oid
	left join pg_description d
	  on d.objoid = c.oid and d.objsubid = a.attnum          -- column comment
	where c.relkind in ('r','p','v','m','f')
	  and n.nspname not in ('pg_catalog','information_schema')
	  and n.nspname not like 'pg_toast%'
	  and a.attnum > 0 and not a.attisdropped
	  and d.description is not null
)
	select *
	from sead_utility.table_columns tc
	left join column_comments cc
	on tc.table_schema = cc.schema
	and tc.table_name = cc.table_name
	and tc.column_name = cc.column_name
	where tc.table_schema = 'public'
	and tc.table_name like 'tbl_%'

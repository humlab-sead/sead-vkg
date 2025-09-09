
drop function if exists public.get_sample_graph(p_physical_sample_id int);
--select get_sample_graph(63815)
create or replace function public.get_sample_graph(p_physical_sample_id int)
   returns jsonb language plpgsql
stable as
$$
declare v_data jsonb;
  begin

  with
    ps as (
      with sample_horizon as (
        select physical_sample_id, string_agg(horizon_name, ', ') as horizon_name
        from tbl_sample_horizons
        join tbl_horizons using (horizon_id)
        group by physical_sample_id
      ), sample_description as (
        select physical_sample_id, string_agg(format('%s: %s', type_name, description), ', ') as description
        from tbl_sample_descriptions
        join tbl_sample_description_types using (sample_description_type_id)
        group by physical_sample_id
      )
      select physical_sample_id,
            type_name as sample_type,
            sample_name,
            alt_ref_type_id,
            sample_group_id,
            horizon_name,
            sample_description.description
      from tbl_physical_samples
      join tbl_sample_types using (sample_type_id)
      left join sample_horizon using (physical_sample_id) 
      left join sample_description using (physical_sample_id)
      where TRUE
        and physical_sample_id = p_physical_sample_id
        --and sample_name = 'A017-005'
    ),
    -- TOTO: add sample dimensions, and sample dimension methods?
    sg as (
      select g.site_id,
            g.sample_group_id,
            g.sample_group_name,
            g.sampling_context_id,
            g.method_id
      from tbl_sample_groups g
      join ps using (sample_group_id)
    ),
    si as (
      select i.site_id, i.site_name, i.site_location_accuracy, i.national_site_identifier,
              json_build_array(i.latitude_dd, i.longitude_dd) as coordinate
      from tbl_sites i
      join sg using (site_id)
      ),
    ae as (
      select a.analysis_entity_id, a.physical_sample_id, a.dataset_id
      from tbl_analysis_entities a
      join ps using (physical_sample_id)
    ),
    av as (
      select analysis_entity_id, analysis_value_id, analysis_value, value_class_id
      from tbl_analysis_values
      join ae using (analysis_entity_id)
      limit 5
    ),
    tc as (
      with identification_level as (
        select abundance_id, string_agg(identification_level_name, ', ') as identification_level
        from tbl_abundance_ident_levels 
        join tbl_identification_levels using (identification_level_id)
        group by abundance_id
      ), modification as (
        select abundance_id, string_agg(modification_type_name, ', ') as modification
        from tbl_abundance_modifications
        join tbl_modification_types using (modification_type_id)
        group by abundance_id
      )
        select analysis_entity_id, abundance_id, taxon_id, abundance as "count", identification_level, modification
        from tbl_abundances
        join ae using (analysis_entity_id)
        left join identification_level using (abundance_id)
        left join modification using (abundance_id)
        limit 5
    ),
    mv as (
      select measured_value_id, analysis_entity_id, measured_value
      from tbl_measured_values
      join ae using (analysis_entity_id)
      limit 5
    ),
    rd as (
      select relative_date_id,
      		 analysis_entity_id,
      		 relative_age_name,
    		 case when coalesce(c14_age_older::bigint, c14_age_younger::bigint) is not null then
        		    format('%s-%s', coalesce(to_char(c14_age_older, 'FM999999999990'), ''), coalesce(to_char(c14_age_younger, 'FM999999999990'), ''))
              else
    		        format('%s-%s', coalesce(to_char(cal_age_older, 'FM999999999990'), ''), coalesce(to_char(cal_age_younger, 'FM999999999990'), ''))
    		 end as dating,
    		 age_type
      from tbl_relative_dates rd
      join tbl_relative_ages ra using (relative_age_id)
      join tbl_relative_age_types rt using (relative_age_type_id)
      join ae using (analysis_entity_id)
    ),
    gc as (
    	select geochron_id, analysis_entity_id, lab_number, age::int,
    		case when coalesce(error_older, error_younger) is null
    			 then null
    			 else
    				json_build_array(error_older::bigint, error_younger::bigint)
    		end as error, delta_13c, international_lab_id as lab_id, notes
    	from tbl_geochronology
    	join tbl_dating_labs using (dating_lab_id)
        join ae using (analysis_entity_id)		
    ),
    vc as (
      select value_class_id, c.name, c.method_id, t.name as value_type
      from tbl_value_classes c
      join tbl_value_types t using (value_type_id)
      where value_class_id in (select value_class_id from av)
    ),
    ds as (
      select  d.dataset_id,
              d.dataset_name,
              dt.data_type_name as data_type,
              dm.master_name,
              d.master_set_id,
              d.method_id,
              d.biblio_id,
              d.project_id,
              dm.biblio_id as master_biblio_id
      from tbl_datasets d
      join tbl_data_types dt using (data_type_id)
      join tbl_dataset_masters dm using (master_set_id)
      join ae using (dataset_id)
    ),
    sl as (
      select l.location_id,
            t.location_type,
            l.location_name,
            si.site_id
      from tbl_locations l
      join tbl_location_types t using (location_type_id)
      join tbl_site_locations sl using (location_id)
      join si using (site_id)
    ),
    f as (
      select f.feature_id, ps.physical_sample_id, f.feature_name, f.feature_description, ft.feature_type_name
      from tbl_features f
      join tbl_physical_sample_features psf using (feature_id)
      join ps using (physical_sample_id)
      join tbl_feature_types ft using (feature_type_id)
    ),
    p as (
      select p.project_id, p.project_name, ds.dataset_id
      from tbl_projects p
      join ds using (project_id)
    ),
    aem as (
      select analysis_entity_id, method_id
      from tbl_analysis_entity_prep_methods
      join ae using (analysis_entity_id)
    ),
    /* publications */
    m as (
      select method_id, method_name, record_type_name as record_type, biblio_id
      from tbl_methods
      join tbl_record_types using (record_type_id)
      where method_id in (
        select method_id from ds union all select method_id from sg union all select method_id from aem union all select method_id from vc
      )
    ),
    si_b as (
      select site_id, biblio_id
      from tbl_site_references
      join si using (site_id)
    ),
    sg_b as (
      select sample_group_id, biblio_id
      from tbl_sample_group_references
      join sg using (sample_group_id)
    ),
    b as (
      select biblio_id, case when authors is not null then format('%s (%s).', authors, year) else title end as citation
      from tbl_biblio
      where biblio_id in (
        select biblio_id from si_b
        union
        select biblio_id from ds
        union
        select biblio_id
        from m
        union
        select biblio_id from sg_b
        union
        select biblio_id from aem)
    ),
    t as (
      select taxon_id, species, genus_name, author_name, family_name
      from tbl_taxa_tree_master
      left join tbl_taxa_tree_genera using (genus_id)
      left join tbl_taxa_tree_authors using (author_id)
      left join tbl_taxa_tree_families using (family_id)
      where taxon_id in (select taxon_id from tc)
    )
      select jsonb_build_object(
          'nodes', jsonb_agg(node) FILTER (where node is not null),
          'edges', jsonb_agg(edge) FILTER (where edge is not null)
      ) into v_data
      from (
        /* nodes */
        select jsonb_build_object(
            'id', 'site_' || si.site_id,
            'entity','Site',
            'label', site_name,
            'attrs', jsonb_build_object(
              -- 'name', site_name,
              'national_id', national_site_identifier,
              'accuracy', site_location_accuracy,
              'coordinate', coordinate
            )
          ) as node, null::jsonb as edge from si
        union all
        select jsonb_build_object(
          'id', 'sg_' || sg.sample_group_id,
          'entity', 'SampleGroup',
          'label', sample_group_name,
          'attrs', jsonb_build_object(
            -- 'name', sample_group_name
          )
        ), null::jsonb as edge from sg
        union all
        select jsonb_build_object(
          'id', 'ps_' || ps.physical_sample_id,
          'entity', 'Sample',
          'label', sample_name,
          'attrs', jsonb_build_object(
            -- 'name', sample_name,
            'type', sample_type,
            'horizon_name', horizon_name,
            'description', description
          )
        ), null from ps
        union all
        select jsonb_build_object(
            'id', 'ae_' || ae.analysis_entity_id,
            'entity', 'Analysis',
            'label', ae.analysis_entity_id::text,
            'attrs', jsonb_build_object()
          ), null from ae
        union all
        select jsonb_build_object(
            'id', 'ds_' || ds.dataset_id,
            'entity', 'Dataset',
            'label', dataset_name,
            'attrs', jsonb_build_object(
              -- 'name', dataset_name,
              'master_name', master_name,
              'data_type', data_type
            )
			    ), null from ds
        union all
        select jsonb_build_object(
            'id', 'sl_' || sl.location_id,
            'entity', 'Location',
            'label', location_name,
            'attrs', jsonb_build_object(
              -- 'name', location_name,
              'type', location_type
            )
          ), null from sl
        union all
        select jsonb_build_object(
            'id', 'f_' || f.feature_id,
            'entity', 'Feature',
            'label', feature_name,
            'attrs', jsonb_build_object(
              -- 'name', feature_name,
              'type', feature_type_name
            )
          ), null from f
        union all
        select jsonb_build_object(
            'id', 'p_' || p.project_id,
            'entity', 'Project',
            'label', project_name,
            'attrs', jsonb_build_object(
              -- 'project_name', project_name
            )
          ), null from tbl_projects p where project_id in (select project_id from p)
        union all
        select jsonb_build_object(
            'id', 'm_' || m.method_id,
            'entity', 'Method',
            'label', method_name,
            'attrs', jsonb_build_object(
              -- 'name', method_name,
              'type', record_type
            )
          ), null from m
        union all
        select jsonb_build_object(
              'id', 'b_' || b.biblio_id,
              'entity', 'Bibliography',
              'label', b.biblio_id::text,
              'attrs', jsonb_build_object(
                'citation', coalesce(citation, 'null')
              )
          ), null from b
        union all
        select jsonb_build_object(
            'id', 'av_' || av.analysis_value_id,
            'entity', 'AnalysisValue',
            'label', av.analysis_value_id::text,
            'attrs', jsonb_build_object(
              'analysis_value', coalesce(analysis_value, 'null')
              )
			  ), null from av
        union all
        select jsonb_build_object(
            'id', 'vc_' || vc.value_class_id,
            'entity', 'ValueClass',
            'label', name,
            'attrs', jsonb_build_object(
              -- 'name', name,
              'value_type', value_type
            )
          ), null from vc
        union all -- Abundance / Taxon
        select jsonb_build_object(
            'id', 'tc_' || tc.abundance_id,
            'entity', 'TaxonCount',
            'label', tc.abundance_id::text,
            'attrs', jsonb_build_object(
              'count', tc."count",
              'identification_level', tc.identification_level,
              'modification', tc.modification
            )
          ), null from tc
        union all -- Measured Value
        select jsonb_build_object(
            'id', 'mv_' || mv.measured_value_id,
            'entity', 'MeasuredValue',
            'label', mv.measured_value_id::text,
            'attrs', jsonb_build_object(
              'value', measured_value
            )
          ), null from mv
		    union all -- Dating
        select jsonb_build_object(
            'id', 'rd_' || rd.relative_date_id,
            'entity', 'Dating',
            'label', rd.dating::text,
            'attrs', jsonb_build_object(
              'age_name', relative_age_name,
			        'age_type', age_type
            )
          ), null from rd
		    union all -- Geochronology
        select jsonb_build_object(
            'id', 'gc_' || geochron_id,
            'entity', 'Geochronology',
            'label', age::text,
            'attrs', jsonb_build_object(
              'error', error,
			        'lab_id', lab_id,
			        'lab_number', lab_number,
			        'notes', notes
            )
          ), null from gc
        union all -- Taxon
        select jsonb_build_object(
            'id', 'taxon_' || t.taxon_id,
            'entity', 'Taxon',
            'label', coalesce(species, 'taxon_' || t.taxon_id),
            'attrs', jsonb_build_object(
              'species', species,
              'genus', genus_name,
              'author', author_name,
              'family', family_name
            )
          ), null from t
        /* edges */
        union all -- Sample Group to Site
        select null, jsonb_build_object('source', 'sg_' || sg.sample_group_id,'target', 'site_' || sg.site_id,'rel', 'belongs_to') from sg
        union all -- Sample to Sample Group
        select null, jsonb_build_object('source', 'ps_' || ps.physical_sample_id,'target', 'sg_' || ps.sample_group_id,'rel', 'in_group') from ps
        union all -- Analysis to Sample
        select null, jsonb_build_object('source', 'ae_' || ae.analysis_entity_id,'target', 'ps_' || ae.physical_sample_id,'rel', 'from_sample') from ae
        union all -- Analysis to Dataset
        select null, jsonb_build_object('source', 'ae_' || ae.analysis_entity_id,'target', 'ds_' || ae.dataset_id,'rel', 'in_dataset') from ae
        union all -- Sample to Feature
        select null, jsonb_build_object('source', 'ps_' || f.physical_sample_id,'target', 'f_' || f.feature_id,'rel', 'has_feature') from f
        union all -- Dataset to Project
        select null, jsonb_build_object('source', 'ds_' || p.dataset_id,'target', 'p_' || p.project_id,'rel', 'belongs_to') from p
        union all -- Dataset to Method
        select null, jsonb_build_object('source', 'ds_' || ds.dataset_id,'target', 'm_' || ds.method_id,'rel', 'produced_by') from ds
        union all -- Sample Group Method to Method
        select null, jsonb_build_object('source', 'sg_' || sg.sample_group_id,'target', 'm_' || sg.method_id,'rel', 'uses_method') from sg
        union all -- Site to Publication
        select null, jsonb_build_object('source', 'site_' || site_id,'target', 'b_' || biblio_id,'rel', 'has_publication') from si_b
        union all -- Site to Location
        select null, jsonb_build_object('source', 'site_' || sl.site_id,'target', 'sl_' || sl.location_id,'rel', 'has_location') from sl
        union all -- Dataset to Publication
        select null, jsonb_build_object('source', 'ds_' || ds.dataset_id,'target', 'b_' || ds.biblio_id,'rel', 'has_publication') from ds
        union all -- Method to Publication
        select null, jsonb_build_object('source', 'm_' || m.method_id,'target', 'b_' || m.biblio_id,'rel', 'described_in') from m
        union all -- Sample Group to Publication
        select null, jsonb_build_object('source', 'sg_' || sample_group_id,'target', 'b_' || biblio_id,'rel', 'has_publication') from sg_b
        union all -- Sample Prep Method to Method
        select null, jsonb_build_object('source', 'ae_' || analysis_entity_id,'target', 'm_' || method_id,'rel', 'uses_prep_method') from aem
        union all -- Analysis Value to Analysis Entity
        select null, jsonb_build_object('source', 'av_' || analysis_value_id,'target', 'ae_' || analysis_entity_id,'rel', 'measured_in' ) from av
        union all -- Analysis Value to Value Class
        select null, jsonb_build_object('source', 'av_' || analysis_value_id,'target', 'vc_' || value_class_id,'rel', 'of_type' ) from av
        union all -- Analysis Entity to Taxon Count
        select null, jsonb_build_object('source', 'tc_' || abundance_id,'target', 'ae_' || analysis_entity_id,'rel', 'measured_in' ) from tc
        union all -- Analysis Entity to Measured Value
        select null, jsonb_build_object('source', 'mv_' || measured_value_id,'target', 'ae_' || analysis_entity_id,'rel', 'measured_in' ) from mv
        union all -- Analysis Entity to Dating
        select null, jsonb_build_object('source', 'rd_' || relative_date_id,'target', 'ae_' || analysis_entity_id,'rel', 'dated_in' ) from rd
        union all -- Analysis Entity to Geochronology
        select null, jsonb_build_object('source', 'gc_' || geochron_id, 'target', 'ae_' || analysis_entity_id,'rel', 'dated_in' ) from gc
        union all -- Taxon Count to Taxon
        select null, jsonb_build_object('source', 'tc_' || abundance_id,'target', 'taxon_' || taxon_id,'rel', 'of_taxon' ) from tc
      ) t(node, edge);
	return v_data;
end; $$;

grant execute on function whoami() to postgrest_anon;
GRANT USAGE ON SCHEMA public TO postgrest_anon;
GRANT EXECUTE ON FUNCTION public.get_sample_graph(int) TO postgrest_anon;
NOTIFY pgrst, 'reload schema';

create or replace function public.whoami()
returns table (user_name text, search_path text)
language plpgsql
stable
as $$
begin
  return query
  select current_user::text, current_setting('search_path')::text;
end;
$$;

GRANT USAGE ON SCHEMA public TO postgrest_anon;
GRANT EXECUTE ON FUNCTION public.whoami() TO postgrest_anon;

NOTIFY pgrst, 'reload schema';
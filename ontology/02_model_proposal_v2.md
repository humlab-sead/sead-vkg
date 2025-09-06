Of course. This is an excellent next step, as `Location` and `Feature` provide crucial context for the archaeological data.

Based on the foreign key constraints you've provided, I can see how these entities connect:
*   A **Site** is linked to one or more **Locations** via the `tbl_site_locations` join table.
*   A **Physical Sample** is linked to one or more **Features** via the `tbl_physical_sample_features` join table.
*   A **Feature** is classified by a **Feature Type**.

Here is the updated proposal, incorporating these new entities into both the ontology and the OBDA model.

---

### Part 1: Updated SEAD Ontology

I'll add the new classes and properties to our proposed ontology.

**New Classes:**

*   `sead:Location`
    *   Represents a named geographical area, such as a country, region, or administrative unit.
    *   Mapped from `tbl_locations`.
*   `sead:Feature`
    *   Represents an immovable archaeological feature from which a sample might be taken (e.g., a well, hearth, pit, or structure).
    *   Mapped from `tbl_features`.
*   `sead:FeatureType`
    *   A classification for a feature (e.g., 'Burial', 'Post hole', 'Ditch'). This acts as a controlled vocabulary.
    *   Mapped from `tbl_feature_types`.

**New Object Properties (Relationships):**

*   `sead:isLocatedIn` (Domain: `sead:Site`, Range: `sead:Location`)
    *   Specifies that a site is situated within a broader geographical location.
*   `sead:wasTakenFrom` (Domain: `sead:PhysicalSample`, Range: `sead:Feature`)
    *   Specifies the exact archaeological feature that a sample originated from.

**New Data Properties (Attributes):**

*   `sead:locationName` (xsd:string)
*   `sead:locationType` (xsd:string)
*   `sead:featureName` (xsd:string)
*   `sead:featureTypeName` (xsd:string)
*   `rdfs:comment` will be used for descriptive text.

---

### Part 2: Updated SEAD OBDA Model (`sead.obda`)

Here is the complete `.obda` file from the previous answer, now with the new mappings for `Location` and `Feature` entities and their relationships. The new additions are in a clearly marked section.

```obda
# =========================================================================
# Ontop OBDA Mapping File for the SEAD Database
# =========================================================================

[PrefixDeclaration]
prefix	:           <http://sead.org/ontology#>
prefix	inst:       <http://sead.org/data#>
prefix	rdf:        <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
prefix	rdfs:       <http://www.w3.org/2000/01/rdf-schema#>
prefix	xsd:        <http://www.w3.org/2001/XMLSchema#>

[SourceDeclaration]
# Replace these with your actual database connection details
sourceUri		sead-db
connectionUrl	jdbc:postgresql://localhost:5432/sead_database
username		db_user
password		db_password
driverClass		org.postgresql.Driver

[MappingDeclaration]

# -------------------------------------------------------------------------
# MAPPING CORE ENTITIES
# -------------------------------------------------------------------------

# Map archaeological Sites
mappingId	Site-Mapping
target		inst:site/{site_id} rdf:type :Site .
			inst:site/{site_id} rdfs:label "Site: {site_name}" .
			inst:site/{site_id} :siteName "{site_name}"^^xsd:string .
			inst:site/{site_id} :latitude "{latitude_dd}"^^xsd:decimal .
			inst:site/{site_id} :longitude "{longitude_dd}"^^xsd:decimal .
source		SELECT site_id, site_name, latitude_dd, longitude_dd FROM tbl_sites WHERE site_name IS NOT NULL

# Map Physical Samples and link them to Sites via Sample Groups
mappingId	PhysicalSample-Mapping
target		inst:sample/{physical_sample_id} rdf:type :PhysicalSample .
			inst:sample/{physical_sample_id} rdfs:label "Sample: {sample_name}" .
			inst:sample/{physical_sample_id} :sampleName "{sample_name}"^^xsd:string .
			inst:sample_group/{sample_group_id} :hasSample inst:sample/{physical_sample_id} .
source		SELECT physical_sample_id, sample_name, sample_group_id FROM tbl_physical_samples

# Map Sample Groups and link them to Sites
mappingId	SampleGroup-Mapping
target		inst:sample_group/{sample_group_id} rdf:type :SampleGroup .
			inst:sample_group/{sample_group_id} rdfs:label "Sample Group: {sample_group_name}" .
			inst:site/{site_id} :hasSampleGroup inst:sample_group/{sample_group_id} .
source		SELECT sample_group_id, sample_group_name, site_id FROM tbl_sample_groups

# Map Analysis Entities and link them to Physical Samples
mappingId	AnalysisEntity-Mapping
target		inst:analysis/{analysis_entity_id} rdf:type :AnalysisEntity .
			inst:sample/{physical_sample_id} :hasAnalysisEntity inst:analysis/{analysis_entity_id} .
			inst:analysis/{analysis_entity_id} :partOfDataset inst:dataset/{dataset_id} .
source		SELECT analysis_entity_id, physical_sample_id, dataset_id FROM tbl_analysis_entities

# Map Datasets and their Methods
mappingId	Dataset-Mapping
target		inst:dataset/{dataset_id} rdf:type :Dataset .
			inst:dataset/{dataset_id} :datasetName "{dataset_name}"^^xsd:string .
			inst:dataset/{dataset_id} :usesMethod inst:method/{method_id} .
source		SELECT dataset_id, dataset_name, method_id FROM tbl_datasets

# Map Methods
mappingId	Method-Mapping
target		inst:method/{method_id} rdf:type :Method .
			inst:method/{method_id} rdfs:label "{method_name}" .
			inst:method/{method_id} :methodName "{method_name}"^^xsd:string .
source		SELECT method_id, method_name FROM tbl_methods WHERE method_name IS NOT NULL

# Map Taxa using a JOIN to get the full scientific name
mappingId	Taxon-Mapping
target		inst:taxon/{taxon_id} rdf:type :Taxon .
			inst:taxon/{taxon_id} rdfs:label "{genus_name} {species}" .
			inst:taxon/{taxon_id} :scientificName "{genus_name} {species}"^^xsd:string .
source		SELECT ttm.taxon_id, ttg.genus_name, ttm.species
			FROM tbl_taxa_tree_master ttm
			JOIN tbl_taxa_tree_genera ttg ON ttm.genus_id = ttg.genus_id
			WHERE ttm.species IS NOT NULL AND ttg.genus_name IS NOT NULL

# -------------------------------------------------------------------------
# MAPPING CONTEXTUAL ENTITIES (LOCATIONS & FEATURES) -- NEWLY ADDED
# -------------------------------------------------------------------------

# Map Locations by joining tbl_locations with tbl_location_types
mappingId   Location-Mapping
target      inst:location/{location_id} rdf:type :Location .
            inst:location/{location_id} rdfs:label "{location_name} ({location_type})" .
            inst:location/{location_id} :locationName "{location_name}"^^xsd:string .
            inst:location/{location_id} :locationType "{location_type}"^^xsd:string .
source      SELECT l.location_id, l.location_name, lt.location_type
            FROM tbl_locations l
            JOIN tbl_location_types lt ON l.location_type_id = lt.location_type_id

# Map Feature Types (the controlled vocabulary for features)
mappingId   FeatureType-Mapping
target      inst:feature_type/{feature_type_id} rdf:type :FeatureType .
            inst:feature_type/{feature_type_id} rdfs:label "{feature_type_name}" .
            inst:feature_type/{feature_type_id} :featureTypeName "{feature_type_name}"^^xsd:string .
source      SELECT feature_type_id, feature_type_name FROM tbl_feature_types

# Map Features and classify them with a specific FeatureType
mappingId   Feature-Mapping
target      inst:feature/{feature_id} rdf:type :Feature .
            inst:feature/{feature_id} rdf:type inst:feature_type/{feature_type_id} .
            inst:feature/{feature_id} rdfs:label "Feature: {feature_name}" .
            inst:feature/{feature_id} :featureName "{feature_name}"^^xsd:string .
            inst:feature/{feature_id} rdfs:comment "{feature_description}"^^xsd:string .
source      SELECT feature_id, feature_name, feature_description, feature_type_id FROM tbl_features

# -------------------------------------------------------------------------
# MAPPING RELATIONSHIPS
# -------------------------------------------------------------------------

# Link Sites to Locations using the tbl_site_locations join table
mappingId   Site-Location-Link
target      inst:site/{site_id} :isLocatedIn inst:location/{location_id} .
source      SELECT site_id, location_id FROM tbl_site_locations

# Link Physical Samples to Features using the tbl_physical_sample_features join table
mappingId   Sample-Feature-Link
target      inst:sample/{physical_sample_id} :wasTakenFrom inst:feature/{feature_id} .
source      SELECT physical_sample_id, feature_id FROM tbl_physical_sample_features

# -------------------------------------------------------------------------
# MAPPING OBSERVATIONS AND MEASUREMENTS (using multi-table JOINs)
# -------------------------------------------------------------------------

# Map Abundance Observations - This is a key mapping linking analyses to taxa and counts.
mappingId	AbundanceObservation-Mapping
target		inst:abundance/{abundance_id} rdf:type :AbundanceObservation .
			inst:analysis/{analysis_entity_id} :hasObservation inst:abundance/{abundance_id} .
			inst:abundance/{abundance_id} :observedTaxon inst:taxon/{taxon_id} .
			inst:abundance/{abundance_id} :abundanceValue "{abundance}"^^xsd:integer .
source		SELECT abundance_id, analysis_entity_id, taxon_id, abundance
			FROM tbl_abundances
			WHERE abundance IS NOT NULL

# Map Absolute Dates (Geochronology) to Analysis Entities
mappingId	AbsoluteDating-Mapping
target		inst:geochron/{geochron_id} rdf:type :GeochronologicalMeasurement .
			inst:analysis/{analysis_entity_id} :hasAbsoluteDate inst:geochron/{geochron_id} .
			inst:geochron/{geochron_id} :age "{age}"^^xsd:integer .
			inst:geochron/{geochron_id} :ageErrorOlder "{error_older}"^^xsd:integer .
			inst:geochron/{geochron_id} :ageErrorYounger "{error_younger}"^^xsd:integer .
			inst:geochron/{geochron_id} :labNumber "{lab_number}"^^xsd:string .
			inst:geochron/{geochron_id} rdfs:label "Radiometric date ({lab_number})" .
source		SELECT geochron_id, analysis_entity_id, age, error_older, error_younger, lab_number
			FROM tbl_geochronology
			WHERE age IS NOT NULL

# Map Relative Dates to Analysis Entities
mappingId	RelativeDating-Mapping
target		inst:reldate/{relative_date_id} rdf:type :RelativeAgeAssignment .
			inst:analysis/{analysis_entity_id} :hasRelativeDate inst:reldate/{relative_date_id} .
			inst:reldate/{relative_date_id} rdfs:label "Relative Age: {relative_age_name}" .
			inst:reldate/{relative_date_id} :relativeAgeName "{relative_age_name}"^^xsd:string .
source		SELECT
				rd.relative_date_id,
				rd.analysis_entity_id,
				ra.relative_age_name
			FROM tbl_relative_dates rd
			JOIN tbl_relative_ages ra ON rd.relative_age_id = ra.relative_age_id

```

### Example SPARQL Query Using the New Entities

This model now enables much richer contextual queries. For example, you can now ask: **"Find all samples and their names that were taken from features of type 'Well' at sites located in 'Sweden'."**

```sparql
PREFIX : <http://sead.org/ontology#>
PREFIX inst: <http://sead.org/data#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?sample ?sampleName ?featureName
WHERE {
  # 1. Find the location for 'Sweden'
  ?location a :Location ;
            :locationName "Sweden" . # Assuming 'Sweden' exists as a location_name

  # 2. Find all sites located in Sweden
  ?site a :Site ;
        :isLocatedIn ?location .

  # 3. Find the feature type for 'Well'
  ?wellType a :FeatureType ;
            :featureTypeName "Well" . # Assuming 'Well' exists as a feature_type_name

  # 4. Find all features of that type
  ?feature a ?wellType ;
           :featureName ?featureName .

  # 5. Find all samples taken from those features,
  #    ensuring the sample belongs to a group from our site
  ?sample a :PhysicalSample ;
          :sampleName ?sampleName ;
          :wasTakenFrom ?feature .

  # Ensure the sample is from one of the sites in Sweden
  ?site :hasSampleGroup / :hasSample ?sample .
}
```

This demonstrates the power of the Virtual Knowledge Graph: you can navigate complex relationships across many tables using a clear, semantic query, which Ontop will automatically translate into an efficient SQL query with all the necessary `JOIN`s.
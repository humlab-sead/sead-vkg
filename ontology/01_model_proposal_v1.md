Excellent request. This is a perfect use case for Ontology-Based Data Access. The SEAD database is rich and complex, making it a great candidate for a Virtual Knowledge Graph.

Here is a comprehensive proposal, broken down into two parts as requested:

1.  **A Proposed Ontology:** Defining the key classes and properties to represent the core archaeological concepts in the database.
2.  **A Proposed OBDA Model:** The `.obda` file that maps this ontology to your database schema.

---

### Part 1: Proposed SEAD Ontology

An ontology provides a formal, shared understanding of a domain. For the SEAD database, the core concepts revolve around **Sites**, the **Samples** taken from them, the **Analyses** performed on those samples, and the **Results** of those analyses, such as taxon abundances and dates.

Here is a proposal for a simple but powerful core ontology.

**Prefixes:**
*   `sead`: `<http://sead.org/ontology#>` (The ontology/vocabulary itself)
*   `sead-inst`: `<http://sead.org/data#>` (The base for instance URIs)
*   `rdfs`: `<http://www.w3.org/2000/01/rdf-schema#>`
*   `owl`: `<http://www.w3.org/2002/07/owl#>`
*   `xsd`: `<http://www.w3.org/2001/XMLSchema#>`

#### Core Classes

*   `sead:Site`
    *   Represents an archaeological site or sampling location.
    *   Mapped from `tbl_sites`.
*   `sead:SampleGroup`
    *   A collection of related samples, like a core or profile.
    *   Mapped from `tbl_sample_groups`.
*   `sead:PhysicalSample`
    *   A physical sample collected from a site, belonging to a sample group.
    *   Mapped from `tbl_physical_samples`.
*   `sead:AnalysisEntity`
    *   A crucial "virtual" entity linking a physical sample to a specific dataset/proxy analysis. This acts as a central hub.
    *   Mapped from `tbl_analysis_entities`.
*   `sead:Dataset`
    *   A collection of analyses, often using a specific method.
    *   Mapped from `tbl_datasets`.
*   `sead:Taxon`
    *   A biological taxon (species, genus, etc.).
    *   Mapped from `tbl_taxa_tree_master` and related tables.
*   `sead:AbundanceObservation`
    *   An observation recording the abundance of a specific taxon in an analysis. We model this as a class (a reification) because the observation itself has multiple properties (the taxon, the count, the element counted).
    *   Mapped from `tbl_abundances`.
*   `sead:GeochronologicalMeasurement`
    *   An absolute date (e.g., Radiocarbon) for an analysis entity.
    *   Mapped from `tbl_geochronology`.
*   `sead:RelativeAgeAssignment`
    *   A relative date (e.g., 'Bronze Age') assigned to an analysis entity.
    *   Mapped from `tbl_relative_dates`.
*   `sead:Method`
    *   An analysis, sampling, or dating method.
    *   Mapped from `tbl_methods`.

#### Object Properties (Relationships between Classes)

*   `sead:hasSampleGroup` (Domain: `sead:Site`, Range: `sead:SampleGroup`)
*   `sead:hasSample` (Domain: `sead:SampleGroup`, Range: `sead:PhysicalSample`)
*   `sead:hasAnalysisEntity` (Domain: `sead:PhysicalSample`, Range: `sead:AnalysisEntity`)
*   `sead:partOfDataset` (Domain: `sead:AnalysisEntity`, Range: `sead:Dataset`)
*   `sead:usesMethod` (Domain: `sead:Dataset`, Range: `sead:Method`)
*   `sead:hasObservation` (Domain: `sead:AnalysisEntity`, Range: `sead:AbundanceObservation`)
*   `sead:observedTaxon` (Domain: `sead:AbundanceObservation`, Range: `sead:Taxon`)
*   `sead:hasAbsoluteDate` (Domain: `sead:AnalysisEntity`, Range: `sead:GeochronologicalMeasurement`)
*   `sead:hasRelativeDate` (Domain: `sead:AnalysisEntity`, Range: `sead:RelativeAgeAssignment`)

#### Data Properties (Attributes with Literal Values)

*   `sead:siteName` (xsd:string)
*   `sead:latitude` (xsd:decimal)
*   `sead:longitude` (xsd:decimal)
*   `sead:sampleName` (xsd:string)
*   `sead:datasetName` (xsd:string)
*   `sead:scientificName` (xsd:string)
*   `sead:abundanceValue` (xsd:integer)
*   `sead:labNumber` (xsd:string)
*   `sead:age` (xsd:integer)
*   `sead:ageErrorOlder` (xsd:integer)
*   `sead:ageErrorYounger` (xsd:integer)
*   `sead:relativeAgeName` (xsd:string)
*   `sead:methodName` (xsd:string)

---

### Part 2: Proposed SEAD OBDA Model (`sead.obda`)

This `.obda` file implements the ontology above by mapping it to your database schema. It focuses on the core entities and their most important relationships, demonstrating simple mappings, multi-table joins, and the creation of complex entities.

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

### How to Use and Extend This Model

1.  **Save the Files:** You would save the ontology (e.g., as `sead.ttl`) and the OBDA model (as `sead.obda`).
2.  **Load in Ontop:** Load these files, along with an OWL file representing your ontology, into an Ontop-powered system (like the Protégé plugin or a standalone SPARQL endpoint).
3.  **Query with SPARQL:** You can now query your database using the ontology terms. For example, to find all taxon abundances from a specific site:

    ```sparql
    PREFIX : <http://sead.org/ontology#>
    PREFIX inst: <http://sead.org/data#>

    SELECT ?taxonName ?abundanceValue
    WHERE {
      # Start from a specific site
      ?site a :Site ;
            :siteName "My Favorite Site" ;
            :hasSampleGroup / :hasSample / :hasAnalysisEntity ?analysis .

      # Find observations linked to that analysis
      ?analysis :hasObservation ?observation .

      # Get the details of the observation
      ?observation :observedTaxon ?taxon ;
                   :abundanceValue ?abundanceValue .

      ?taxon :scientificName ?taxonName .
    }
    ```

4.  **Extension:** This model is a starting point. You can easily extend it by:
    *   Adding more classes (`:Project`, `:Feature`, `:Contact`).
    *   Mapping more properties (e.g., `description` columns, notes).
    *   Adding more complex relationships, such as linking datasets to bibliographic references (`tbl_biblio`).
    *   Modeling the full taxonomic tree (`order` -> `family` -> `genus` -> `species`).
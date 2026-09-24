
# SEAD Virtual Knowledge Graph (VKG)

__Jag har nu integrerat Ontop i supersead. Mapping- och ontologi-filerna är autogenererade och kanske behöver tweakas, de finns i /home/sead/supersead.humlab.umu.se/ontop/models på seadserv.
 
Här är ett testkommando som bör fungera att köra från en terminal:
 
curl -X POST   -H "Content-Type: application/sparql-query"   --data 'SELECT ?site WHERE { ?site a <https://supersead.humlab.umu.se/tbl_sites> } LIMIT 10'   https://supersead.humlab.u
mu.se/sparql__

[![License: MIT](https://img.shields.io/badge/Code%20License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Data License: CC BY 4.0](https://img.shields.io/badge/Data%20License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

This repository contains the complete configuration for the **SEAD (Strategic Environmental Archaeology Database) Virtual Knowledge Graph**. It uses the [Ontop](https://ontop-vkg.org/) platform to create a standards-compliant SPARQL endpoint over the existing SEAD relational database, without duplicating or migrating any data.

This project transforms SEAD's rich archaeological and environmental data into a web-native, queryable resource, making it fully compliant with the [FAIR data principles](https://www.go-fair.org/fair-principles/) (Findable, Accessible, Interoperable, and Reusable).

---

## ✨ Key Features

*   **Live & Synchronized:** The SPARQL endpoint queries the SEAD database directly. Any changes in the source database are immediately reflected in the knowledge graph.
*   **Powerful & Expressive Queries:** Go beyond simple table lookups. Ask complex, cross-domain questions about sites, samples, taxonomy, and chronology in a single query.
*   **Standardized Vocabulary:** Data is exposed using a combination of a custom SEAD ontology and world-class standard vocabularies, including **CIDOC-CRM**, **GeoSPARQL**, and **Darwin Core**.
*   **Interoperable Data:** By using standard ontologies, SEAD data can be easily integrated with other cultural heritage and biodiversity datasets from around the world.

---

## 🌍 Public SPARQL Endpoint

The easiest way to explore the SEAD Knowledge Graph is through our public SPARQL endpoint. You can use any SPARQL-compliant client, but we recommend the user-friendly [YASGUI](https://yasgui.triply.cc/) web client.

> **Endpoint URL:** https://sparql.sead.org/ (_Note: This is a placeholder URL_)
>
> **[Click here to query the SEAD VKG in YASGUI](https://yasgui.triply.cc/#query=PREFIX%20crm%3A%20%3Chttp%3A%2F%2Fwww.cidoc-crm.org%2Fcidoc-crm%2F%3E%0APREFIX%20dcterms%3A%20%3Chttp%3A%2F%2Fpurl.org%2Fdc%2Fterms%2F%3E%0A%0ASELECT%20%3Fsite%20%3FsiteName%20%3Fdescription%0AWHERE%20%7B%0A%20%20%3Fsite%20a%20crm%3AE27_Site%20%3B%0A%20%20%20%20%20%20%20%20dcterms%3Atitle%20%3FsiteName%20%3B%0A%20%20%20%20%20%20%20%20dcterms%3Adescription%20%3Fdescription%20.%0A%7D%0ALIMIT%2010&endpoint=https%3A%2F%2Fsparql.sead.org%2F)**

---

## 🏗️ Ontology Model

The SEAD VKG is built upon a formal ontology that defines the types of entities and their relationships. The core concepts include:

*   **`sead:Site`** (**`crm:E27_Site`**, **`gsp:Feature`**): An archaeological site with a geographic location.
*   **`sead:Feature`** (**`crm:E25_Man-Made_Feature`**): An immovable archaeological feature (e.g., a well, hearth, or pit).
*   **`sead:PhysicalSample`** (**`crm:E22_Human-Made_Object`**): A physical sample taken from a site.
*   **`dwc:Occurrence`**: An observation of a taxon at a particular place and time, including its abundance (**`dwc:individualCount`**).
*   **`dwc:Taxon`**: A biological taxon with a **`dwc:scientificName`**.
*   **`crm:E16_Measurement`**: An absolute date (e.g., Radiocarbon) associated with a sample.

These concepts are linked using properties from standard ontologies where possible, such as **`crm:P89_falls_within`** (for site location) and **`dcterms:title`**.

For a detailed view, see the ontology source file: [`/ontology/sead-ontology.ttl`](./ontology/sead-ontology.ttl).

---

## 🚀 Getting Started (Local Setup)

If you want to run the SPARQL endpoint on your own machine for development or testing, you have two options.

### Option 1: Running with Docker (Recommended) 🐳

This is the simplest method. It requires [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/install/).

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-org/sead-ontop-vkg.git
    cd sead-ontop-vkg
    ```

2.  **Configure the database connection:**
    Edit the `ontop/sead.properties` file and replace the placeholder JDBC credentials with your actual database connection details.

3.  **Launch the service:**
    ```bash
    docker-compose up
    ```

This will start an Ontop SPARQL endpoint. You can access it in your browser at:
**`http://localhost:8080`**

### Option 2: Running Manually with the Ontop CLI

This method is for advanced users or those who cannot use Docker.

1.  **Download Ontop:** Get the latest Ontop CLI distribution (**`ontop-cli-X.Y.Z.zip`**) from the [Ontop GitHub Releases](https://github.com/ontop/ontop/releases). Unzip it.

2.  **Configure:** Place the **`sead.obda`**, **`sead.properties`**, and **`sead-ontology.ttl`** files from this repository into a directory. Ensure the database credentials in **`sead.properties`** are correct.

3.  **Run the endpoint:**
    From your terminal, navigate to the unzipped Ontop directory and run:
    ```bash
    ./ontop-endpoint -m /path/to/your/sead.obda \
                     -p /path/to/your/sead.properties \
                     -t /path/to/your/sead-ontology.ttl
    ```

The endpoint will be available at **`http://localhost:8080`**.

---

## 💡 Example Queries

Here are a few queries to demonstrate the power of the SEAD VKG. You can find more in the [`/examples/`](./examples/) directory.

### 1. Find all samples from features classified as 'Well'

This query demonstrates linking samples to features and their types.

```sparql
PREFIX : <http://sead.org/ontology#>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

SELECT ?sampleName ?featureName ?siteName
WHERE {
  ?wellType skos:prefLabel "Well"@en .

  ?feature dcterms:type ?wellType ;
           dcterms:title ?featureName .

  ?sample a :PhysicalSample ;
          dcterms:title ?sampleName ;
          :wasTakenFrom ?feature .

  # Traverse up to the site for context
  ?site :hasSampleGroup / :hasSample ?sample ;
        dcterms:title ?siteName .
}
LIMIT 20
```

### 2. Get insect abundances from sites in Sweden

This query combines taxonomic data (`dwc:Occurrence`) with geographic location information.

```sparql
PREFIX dwc: <http://rs.tdwg.org/dwc/terms/>
PREFIX crm: <http://www.cidoc-crm.org/cidoc-crm/>
PREFIX : <http://sead.org/ontology#>

SELECT ?siteName ?scientificName ?count
WHERE {
  ?location dcterms:title "Sweden" .

  ?site a crm:E27_Site ;
        dcterms:title ?siteName ;
        crm:P89_falls_within ?location .

  ?site :hasSampleGroup / :hasSample / :hasAnalysisEntity ?analysis .

  ?occurrence a dwc:Occurrence ;
              dwc:eventID ?analysis ;
              dwc:individualCount ?count ;
              dwc:taxonID ?taxon .

  ?taxon dwc:scientificName ?scientificName .

  # Optional: Filter for insects if a record type is available
  # ?taxon ...
}
ORDER BY DESC(?count)
LIMIT 50
```

---

## 📂 Repository Structure

```
sead-ontop-vkg/
│
├── ontop/                  # Ontop configuration files
│   ├── sead.obda           # The core OBDA mappings
│   └── sead.properties     # Database connection and endpoint settings
│
├── ontology/               # Ontology files
│   └── sead-ontology.ttl   # The SEAD custom ontology
│
├── examples/               # A collection of sample SPARQL queries
│   └── ...
│
├── docker-compose.yml      # Docker file to easily run the endpoint
├── README.md               # This file
└── LICENSE                 # The license for the code in this repository
```

---

## 📜 License

The code in this repository (mapping files, Docker configuration) is licensed under the **MIT License**. See the [LICENSE](./LICENSE) file for details.

The data exposed through the SPARQL endpoint is made available under the **Creative Commons Attribution 4.0 International (CC BY 4.0)** license.

## ✍️ How to Cite

If you use the SEAD Virtual Knowledge Graph in your research, please cite it as follows:

> [Author(s)/SEAD Project Team]. ([Year]). *SEAD Virtual Knowledge Graph*. [URL of this repository or project page].

## 📧 Contact & Contributing

For questions, bug reports, or suggestions, please open an issue in this repository. We welcome contributions
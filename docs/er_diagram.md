# IMDb Database — Entity Relationship Diagram

This diagram shows the 13 tables in the `core` schema and the relationships between them. Crow's-foot notation: `||--o{` means "one to zero or many."

```mermaid
erDiagram
    title ||--o| title_rating : "has rating"
    title ||--o{ title_episode : "parent of"
    title ||--o{ title_aka : "localized as"
    title ||--o{ title_genre : "tagged with"
    title ||--o{ title_director : "directed by"
    title ||--o{ title_writer : "written by"
    title ||--o{ title_principal : "features"
    title ||--o{ person_known_for : "appears in"

    person ||--o{ title_director : "directs"
    person ||--o{ title_writer : "writes"
    person ||--o{ title_principal : "performs in"
    person ||--o{ person_profession : "has"
    person ||--o{ person_known_for : "known for"

    genre ||--o{ title_genre : "applied to"
    profession ||--o{ person_profession : "held by"

    title {
        varchar tconst PK
        varchar title_type
        text primary_title
        text original_title
        boolean is_adult
        smallint start_year
        smallint end_year
        integer runtime_minutes
    }

    person {
        varchar nconst PK
        text primary_name
        smallint birth_year
        smallint death_year
    }

    title_rating {
        varchar tconst PK
        numeric average_rating
        integer num_votes
    }

    title_episode {
        varchar tconst PK
        varchar parent_tconst FK
        smallint season_number
        smallint episode_number
    }

    title_aka {
        varchar tconst PK
        smallint ordering PK
        text title
        varchar region
        varchar language
        text types
        text attributes
        boolean is_original_title
    }

    genre {
        serial genre_id PK
        varchar genre_name
    }

    profession {
        serial profession_id PK
        varchar profession_name
    }

    title_genre {
        varchar tconst PK
        integer genre_id PK
    }

    title_director {
        varchar tconst PK
        varchar nconst PK
    }

    title_writer {
        varchar tconst PK
        varchar nconst PK
    }

    title_principal {
        varchar tconst PK
        smallint ordering PK
        varchar nconst FK
        varchar category
        text job
        jsonb characters
    }

    person_profession {
        varchar nconst PK
        integer profession_id PK
    }

    person_known_for {
        varchar nconst PK
        varchar tconst PK
    }
```
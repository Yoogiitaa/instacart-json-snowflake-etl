-- Create database
CREATE DATABASE IF NOT EXISTS INSTACART_DB;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS INSTACART_DB.RAW;
CREATE SCHEMA IF NOT EXISTS INSTACART_DB.ANALYTICS;

-- Set working context
USE DATABASE INSTACART_DB;
USE SCHEMA RAW;

-- Create an internal stage
CREATE OR REPLACE STAGE INSTACART_JSON_STAGE;

-- Create JSON file format
CREATE OR REPLACE FILE FORMAT JSON_FORMAT
    TYPE = JSON
    STRIP_OUTER_ARRAY = TRUE;

-- Create raw events table
CREATE OR REPLACE TABLE RAW_EVENTS (
    EVENT_DATA VARIANT,
    LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO RAW_EVENTS (EVENT_DATA)
FROM @INSTACART_JSON_STAGE/case.json
FILE_FORMAT = (FORMAT_NAME = JSON_FORMAT);

SELECT *
FROM RAW_EVENTS
LIMIT 10;

SELECT
    EVENT_DATA:EventName::STRING AS EVENT_NAME,
    COUNT(*) AS TOTAL_RECORDS
FROM RAW_EVENTS
GROUP BY EVENT_NAME
ORDER BY total_records DESC;

SELECT
    TYPEOF(EVENT_DATA:Payload) AS PAYLOAD_TYPE,
    COUNT(*) AS RECORD_COUNT
FROM RAW_EVENTS
GROUP BY 1;


SELECT
    EVENT_DATA:EventName::STRING AS EVENT_NAME,
    EVENT_DATA:Payload::STRING AS RAW_PAYLOAD,
    PARSE_JSON(EVENT_DATA:Payload::STRING) AS PARSED_PAYLOAD
FROM RAW_EVENTS
LIMIT 5;

SELECT
    PARSE_JSON(EVENT_DATA:Payload::STRING):provider::STRING
        AS PROVIDER,

    PARSE_JSON(EVENT_DATA:Payload::STRING):offerId::STRING
        AS OFFER_ID

FROM RAW_EVENTS
WHERE EVENT_DATA:EventName::STRING = 'DynamicPrice_Result';


USE SCHEMA INSTACART_DB.ANALYTICS;

CREATE OR REPLACE TABLE CURATED_OFFER_OPTIONS AS

WITH PARSED_EVENTS AS (
    SELECT
        EVENT_DATA:EventName::STRING AS EVENT_NAME,

        TRY_PARSE_JSON(
            EVENT_DATA:Payload::STRING
        ) AS PAYLOAD,

        TO_CHAR(
            DATEADD(
                HOUR,
                -3,
                TO_TIMESTAMP_NTZ(
                    REPLACE(
                        EVENT_DATA:EnqueuedTimeUtc::STRING,
                        ' UTC',
                        ''
                    ),
                    'YYYY-MM-DD HH24:MI:SS'
                )
            ),
            'DD/MM/YYYY'
        ) AS ENQUEUED_TIMESP

    FROM INSTACART_DB.RAW.RAW_EVENTS

    WHERE EVENT_DATA:EventName::STRING = 'CurateOffer_Result'
),

CURATION_DATA AS (
    SELECT
        P.ENQUEUED_TIMESP,
        C.VALUE AS CURATION

    FROM PARSED_EVENTS P,
    LATERAL FLATTEN(INPUT => P.PAYLOAD) C
),

OPTION_DATA AS (
    SELECT
        C.ENQUEUED_TIMESP,
        C.CURATION,
        O.VALUE AS OPTION_DATA

    FROM CURATION_DATA C,
    LATERAL FLATTEN(INPUT => C.CURATION:options) O
)

SELECT
    CURATION:curationProvider::STRING AS "CurationProvider",
    CURATION:offerId::STRING AS "OfferId",
    CURATION:dealerId::STRING AS "DealerId",

    OPTION_DATA:uniqueOptionId::STRING AS "UniqueOptionId",
    OPTION_DATA:optionId::STRING AS "OptionId",

    OPTION_DATA:isMobileDealer::BOOLEAN AS "IsMobileDealer",
    OPTION_DATA:isOpen::BOOLEAN AS "IsOpen",

    OPTION_DATA:eta::STRING AS "Eta",

    OPTION_DATA:chamaScore::NUMBER(10,2) AS "ChamaScore",

    OPTION_DATA:productBrand::STRING AS "ProductBrand",

    OPTION_DATA:isWinner::BOOLEAN AS "IsWinner",

    OPTION_DATA:minimumPrice::NUMBER(10,2) AS "MinimumPrice",
    OPTION_DATA:maximumPrice::NUMBER(10,2) AS "MaximumPrice",
    OPTION_DATA:dynamicPrice::NUMBER(10,2) AS "DynamicPrice",
    OPTION_DATA:finalPrice::NUMBER(10,2) AS "FinalPrice",

    OPTION_DATA:defeatPrimaryReason::STRING AS "DefeatPrimaryReason",

    ARRAY_TO_STRING(
        AS_ARRAY(OPTION_DATA:defeatReasons),
        ','
    ) AS "DefeatReasons",

    ENQUEUED_TIMESP AS "EnqueuedTimeSP"

FROM OPTION_DATA;

SELECT
    "UniqueOptionId",
    COUNT(*) AS RECORD_COUNT
FROM CURATED_OFFER_OPTIONS
GROUP BY "UniqueOptionId"
HAVING COUNT(*) > 1;

SELECT
    "OfferId",
    COUNT(*) AS TOTAL_OPTIONS
FROM CURATED_OFFER_OPTIONS
GROUP BY "OfferId";


USE SCHEMA INSTACART_DB.ANALYTICS;

CREATE OR REPLACE TABLE DYNAMIC_PRICE_OPTION AS

WITH PARSED_EVENTS AS (
    SELECT
        EVENT_DATA:EventName::STRING AS EVENT_NAME,

        TRY_PARSE_JSON(
            EVENT_DATA:Payload::STRING
        ) AS PAYLOAD,

        TO_CHAR(
            DATEADD(
                HOUR,
                -3,
                TO_TIMESTAMP_NTZ(
                    REPLACE(
                        EVENT_DATA:EnqueuedTimeUtc::STRING,
                        ' UTC',
                        ''
                    ),
                    'YYYY-MM-DD HH24:MI:SS'
                )
            ),
            'DD/MM/YYYY'
        ) AS ENQUEUED_TIMESP

    FROM INSTACART_DB.RAW.RAW_EVENTS

    WHERE EVENT_DATA:EventName::STRING = 'DynamicPrice_Result'
),

FILTERED_EVENTS AS (
    SELECT *
    FROM PARSED_EVENTS
    WHERE PAYLOAD:provider::STRING = 'ApplyDynamicPricePerOption'
),

OPTION_DATA AS (
    SELECT
        P.PAYLOAD:provider::STRING AS PROVIDER,
        P.PAYLOAD:offerId::STRING AS OFFER_ID,
        F.VALUE AS OPTION_DATA,
        P.ENQUEUED_TIMESP

    FROM FILTERED_EVENTS P,
    LATERAL FLATTEN(
        INPUT => P.PAYLOAD:algorithmOutput
    ) F
)

SELECT
    PROVIDER AS "Provider",
    OFFER_ID AS "OfferId",

    OPTION_DATA:uniqueOptionId::STRING AS "UniqueOptionId",

    OPTION_DATA:bestPrice::NUMBER(10,2) AS "BestPrice",

    ENQUEUED_TIMESP AS "EnqueuedTimeSP"

FROM OPTION_DATA;


SELECT COUNT(*) AS TOTAL_RECORDS
FROM DYNAMIC_PRICE_OPTION;


USE SCHEMA INSTACART_DB.ANALYTICS;

CREATE OR REPLACE TABLE DYNAMIC_PRICE_RANGE AS

WITH PARSED_EVENTS AS (
    SELECT
        TRY_PARSE_JSON(
            EVENT_DATA:Payload::STRING
        ) AS PAYLOAD,

        TO_CHAR(
            DATEADD(
                HOUR,
                -3,
                TO_TIMESTAMP_NTZ(
                    REPLACE(
                        EVENT_DATA:EnqueuedTimeUtc::STRING,
                        ' UTC',
                        ''
                    ),
                    'YYYY-MM-DD HH24:MI:SS'
                )
            ),
            'DD/MM/YYYY'
        ) AS ENQUEUED_TIMESP

    FROM INSTACART_DB.RAW.RAW_EVENTS

    WHERE EVENT_DATA:EventName::STRING = 'DynamicPrice_Result'
),

FILTERED_EVENTS AS (
    SELECT *
    FROM PARSED_EVENTS
    WHERE PAYLOAD:provider::STRING = 'ApplyDynamicPriceRange'
)

SELECT
    PAYLOAD:provider::STRING AS "Provider",

    PAYLOAD:offerId::STRING AS "OfferId",

    PAYLOAD:algorithmOutput:min_global::NUMBER(10,2)
        AS "MinGlobal",

    PAYLOAD:algorithmOutput:min_recommended::NUMBER(10,2)
        AS "MinRecommended",

    PAYLOAD:algorithmOutput:max_recommended::NUMBER(10,2)
        AS "MaxRecommended",

    PAYLOAD:algorithmOutput:differenceMinRecommendMinTheory::NUMBER(10,2)
        AS "DifferenceMinRecommendMinTheory",

    ENQUEUED_TIMESP AS "EnqueuedTimeSP"

FROM FILTERED_EVENTS;


SELECT
    'CURATED_OFFER_OPTIONS' AS TABLE_NAME,
    COUNT(*) AS TOTAL_RECORDS
FROM CURATED_OFFER_OPTIONS

UNION ALL

SELECT
    'DYNAMIC_PRICE_OPTION',
    COUNT(*)
FROM DYNAMIC_PRICE_OPTION

UNION ALL

SELECT
    'DYNAMIC_PRICE_RANGE',
    COUNT(*)
FROM DYNAMIC_PRICE_RANGE;


CREATE OR REPLACE STAGE INSTACART_OUTPUT_STAGE;




LIST @INSTACART_DB.RAW.INSTACART_OUTPUT_STAGE;

--1st
COPY INTO @INSTACART_DB.RAW.INSTACART_OUTPUT_STAGE/CuratedOfferOptions.csv
FROM (
    SELECT *
    FROM INSTACART_DB.RAW.CURATED_OFFER_OPTIONS
)
FILE_FORMAT = (
    TYPE = CSV
    FIELD_DELIMITER = ','
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ESCAPE_UNENCLOSED_FIELD = NONE
    NULL_IF = ()
    EMPTY_FIELD_AS_NULL = FALSE
    COMPRESSION = NONE
)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;

--2nd
COPY INTO @INSTACART_DB.RAW.INSTACART_OUTPUT_STAGE/DynamicPriceOption.csv
FROM (
    SELECT *
    FROM INSTACART_DB.RAW.DYNAMIC_PRICE_OPTION
)
FILE_FORMAT = (
    TYPE = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ESCAPE_UNENCLOSED_FIELD = NONE
    NULL_IF = ()
    EMPTY_FIELD_AS_NULL = FALSE
    COMPRESSION = NONE
)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;

--3rd
COPY INTO @INSTACART_DB.RAW.INSTACART_OUTPUT_STAGE/DynamicPriceRange.csv
FROM (
    SELECT *
    FROM INSTACART_DB.RAW.DYNAMIC_PRICE_RANGE
)
FILE_FORMAT = (
    TYPE = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ESCAPE_UNENCLOSED_FIELD = NONE
    NULL_IF = ()
    EMPTY_FIELD_AS_NULL = FALSE
    COMPRESSION = NONE
)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
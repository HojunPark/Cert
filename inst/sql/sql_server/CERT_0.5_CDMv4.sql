/* 
	CERT Query - 0.4
	
	Written and Confirmed by SUNGJAE JUNG
	Created at 2016.03.31
	Edited 1st: 2016.04.08
	Edited 2nd: 2016.05.27
	Edited 3rd: 2016.05.30
	Edited 4th: 2016.06.17
	Edited 4th for CDMv4: 2016.06.17
	Confirmed 4th edition: 2016.07.08
	Edited 5th for CDMv4: 2016.07.21
	Confirmed 5th edition: 2016.xx.xx

*/
USE [SJ_CERT_CDM4];

-- Running
-- # CASE: ATC(Anatomical Therapeutic Chemical Classification)
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].TARGET_DRUG', 'U') IS NOT NULL
	DROP TABLE TARGET_DRUG;
CREATE TABLE TARGET_DRUG(
	DRUG_NAME			VARCHAR(50) NOT NULL,
	DRUG_CLASS			VARCHAR(50) NOT NULL,
	DRUG_CODE			VARCHAR(50) NOT NULL
);
INSERT INTO TARGET_DRUG VALUES('CIPROFLOXACIN','Anatomical Therapeutic Chemical Classification','J01MA02');
INSERT INTO TARGET_DRUG VALUES('CIPROFLOXACIN','Anatomical Therapeutic Chemical Classification','S01AX13');
INSERT INTO TARGET_DRUG VALUES('CIPROFLOXACIN','Anatomical Therapeutic Chemical Classification','S02AA15');
INSERT INTO TARGET_DRUG VALUES('CIPROFLOXACIN','Anatomical Therapeutic Chemical Classification','S03AA07');

IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].DRUG_LIST', 'U') IS NOT NULL
	DROP TABLE DRUG_LIST;
SELECT DISTINCT B.DRUG_NAME, A.DESCENDANT_CONCEPT_ID DRUG_ID
INTO DRUG_LIST
FROM [SCAN].[DBO].CONCEPT_ANCESTOR A
	INNER JOIN (
		SELECT BB.DRUG_NAME, AA.CONCEPT_ID, AA.CONCEPT_CLASS, AA.CONCEPT_CODE
		FROM [SCAN].[DBO].CONCEPT AA
			INNER JOIN TARGET_DRUG BB
			ON AA.CONCEPT_CLASS=BB.DRUG_CLASS
				AND AA.CONCEPT_CODE=BB.DRUG_CODE
	) B
	ON A.ANCESTOR_CONCEPT_ID=B.CONCEPT_ID

-- Running
-- LABTEST_LIST: LOINC Code
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].LABTEST_LIST', 'U') IS NOT NULL
	DROP TABLE LABTEST_LIST;
CREATE TABLE LABTEST_LIST(
	LAB_ID			INT NOT NULL,
	LAB_NAME		VARCHAR(50) NOT NULL,
	ABNORM_TYPE		VARCHAR(20) NOT NULL
);
INSERT INTO LABTEST_LIST VALUES(3018677,'aPTT','Both');
INSERT INTO LABTEST_LIST VALUES(3006923,'ALT','Hyper');
INSERT INTO LABTEST_LIST VALUES(3013721,'AST','Hyper');

/* Use Exposure */
-- VISIT
-- Running
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].VISIT_EXPOSURE_TMP', 'U') IS NOT NULL
	DROP TABLE VISIT_EXPOSURE_TMP;
SELECT DISTINCT A.PERSON_ID, A.VISIT_START_DATE, A.VISIT_END_DATE
	,MIN(B.DRUG_EXPOSURE_START_DATE) OVER(PARTITION BY A.PERSON_ID, A.VISIT_START_DATE, A.VISIT_END_DATE, B.DRUG_NAME) FIRST_DRUG_ORDDATE
	,B.DRUG_EXPOSURE_START_DATE, B.DRUG_NAME
INTO VISIT_EXPOSURE_TMP
FROM (
		SELECT PERSON_ID, VISIT_START_DATE, VISIT_END_DATE 
		FROM [SCAN].[DBO].VISIT_OCCURRENCE 
		WHERE PLACE_OF_SERVICE_CONCEPT_ID IN (9201)
	) A 
	INNER JOIN (
		SELECT AA.PERSON_ID, AA.DRUG_EXPOSURE_START_DATE
			, BB.DRUG_NAME
		FROM [SCAN].[DBO].DRUG_EXPOSURE AA
			INNER JOIN DRUG_LIST BB
			ON AA.DRUG_CONCEPT_ID=BB.DRUG_ID
	) B
	ON A.PERSON_ID=B.PERSON_ID
		AND B.DRUG_EXPOSURE_START_DATE BETWEEN A.VISIT_START_DATE AND A.VISIT_END_DATE

IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].VISIT_EXPOSURE', 'U') IS NOT NULL
	DROP TABLE VISIT_EXPOSURE;
SELECT DISTINCT PERSON_ID, VISIT_START_DATE, VISIT_END_DATE
	, FIRST_DRUG_ORDDATE, DRUG_NAME
INTO VISIT_EXPOSURE
FROM VISIT_EXPOSURE_TMP

-- LAB
-- Running
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].LAB_EXPOSURE', 'U') IS NOT NULL
	DROP TABLE LAB_EXPOSURE;
SELECT DISTINCT A.PERSON_ID, A.FIRST_DRUG_ORDDATE, A.DRUG_NAME
	, B.LAB_NAME, B.OBSERVATION_CONCEPT_ID, B.ABNORM_TYPE, B.RANGE_LOW, B.RANGE_HIGH, B.RESULT
	,CASE WHEN OBSERVATION_DATETIME <= A.FIRST_DRUG_ORDDATE THEN 'Y'
		ELSE 'N'
	END IS_BEFORE
INTO LAB_EXPOSURE
FROM VISIT_EXPOSURE A
	INNER JOIN (
		SELECT AA.PERSON_ID, AA.OBSERVATION_CONCEPT_ID
			, CAST(AA.OBSERVATION_DATE AS DATETIME)+CAST(AA.OBSERVATION_TIME AS DATETIME) OBSERVATION_DATETIME
			, AA.VALUE_AS_NUMBER RESULT, AA.RANGE_LOW, AA.RANGE_HIGH
			, BB.LAB_NAME, BB.ABNORM_TYPE
		FROM (
				SELECT PERSON_ID, OBSERVATION_CONCEPT_ID, OBSERVATION_DATE, OBSERVATION_TIME
					, VALUE_AS_NUMBER, RANGE_LOW, RANGE_HIGH
				FROM [SCAN].[DBO].OBSERVATION
				WHERE RANGE_LOW IS NOT NULL
					AND RANGE_HIGH IS NOT NULL
			) AA
			INNER JOIN LABTEST_LIST BB
			ON AA.OBSERVATION_CONCEPT_ID=BB.LAB_ID 
	) B
	ON A.PERSON_ID=B.PERSON_ID
		AND B.OBSERVATION_DATETIME BETWEEN A.VISIT_START_DATE AND A.VISIT_END_DATE

-- CERT Dataset
-- Running
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].CERT_EXPOSURE', 'U') IS NOT NULL
	DROP TABLE CERT_EXPOSURE;
SELECT A.*
INTO CERT_EXPOSURE
FROM LAB_EXPOSURE A
	INNER JOIN (
		SELECT *
		FROM (
			SELECT PERSON_ID, FIRST_DRUG_ORDDATE, DRUG_NAME, OBSERVATION_CONCEPT_ID
				, RANGE_LOW, RANGE_HIGH, IS_BEFORE
			FROM LAB_EXPOSURE
		) A
		PIVOT (
			COUNT(IS_BEFORE) FOR IS_BEFORE IN (Y,N)
		) PV
		WHERE Y>0 AND N>0) B
	ON A.PERSON_ID=B.PERSON_ID
		AND A.FIRST_DRUG_ORDDATE=B.FIRST_DRUG_ORDDATE
		AND A.DRUG_NAME=B.DRUG_NAME
		AND A.OBSERVATION_CONCEPT_ID=B.OBSERVATION_CONCEPT_ID
		AND A.RANGE_LOW=B.RANGE_LOW
		AND A.RANGE_HIGH=B.RANGE_HIGH

-- Demographics
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].DEMOGRAPHICS', 'U') IS NOT NULL
	DROP TABLE DEMOGRAPHICS;
WITH
CASES(
	PERSON_ID, FIRST_DRUG_ORDDATE, DRUG_NAME
)
AS(
	SELECT DISTINCT PERSON_ID, FIRST_DRUG_ORDDATE, DRUG_NAME 
	FROM CERT_EXPOSURE
),
N_CASES(
	DRUG_NAME, N_CASES
)
AS(
	SELECT DRUG_NAME, COUNT(*) N_CASES
	FROM CASES
	GROUP BY DRUG_NAME
),
N_PRESCRIPTIONS(
	DRUG_NAME, N_PRESCRIPTIONS
)
AS(
	SELECT A.DRUG_NAME, COUNT(*) N_PRESCRIPTIONS
	FROM VISIT_EXPOSURE_TMP A
		INNER JOIN CASES B
		ON A.PERSON_ID=B.PERSON_ID
			AND A.FIRST_DRUG_ORDDATE=B.FIRST_DRUG_ORDDATE
			AND A.DRUG_NAME=B.DRUG_NAME
	GROUP BY A.DRUG_NAME
),
BDAY(
	PERSON_ID, BIRTHDAY
)
AS(
	SELECT DISTINCT A.PERSON_ID
		, CAST(
			CAST(YEAR_OF_BIRTH AS VARCHAR(4))+
			RIGHT('0'+CAST(MONTH_OF_BIRTH AS VARCHAR(2)),2)+
			RIGHT('0'+CAST(DAY_OF_BIRTH AS VARCHAR(2)),2) 
			AS DATETIME
		) BIRTHDAY
	FROM [SCAN].[DBO].PERSON A
		INNER JOIN CASES B
		ON A.PERSON_ID=B.PERSON_ID
),
AGE(
	PERSON_ID, FIRST_DRUG_ORDDATE, DRUG_NAME, AGE
)
AS(
	SELECT DISTINCT A.PERSON_ID, B.FIRST_DRUG_ORDDATE, B.DRUG_NAME
		, DATEDIFF(YY, A.BIRTHDAY, B.FIRST_DRUG_ORDDATE) -
		CASE WHEN DATEADD(YY, DATEDIFF(YY, A.BIRTHDAY, B.FIRST_DRUG_ORDDATE), A.BIRTHDAY)
					> B.FIRST_DRUG_ORDDATE THEN 1
			ELSE 0
		END AGE
	FROM BDAY A
		INNER JOIN CASES B
		ON A.PERSON_ID=B.PERSON_ID
),
AGE_AVG(
	DRUG_NAME, AGE_AVG, AGE_STDEV
)
AS(
	SELECT DRUG_NAME, AVG(AGE) AGE_AVG, ROUND(STDEV(AGE),1) AGE_STDEV
	FROM AGE
	GROUP BY DRUG_NAME
),
AGE_GROUP(
	DRUG_NAME, AGE_GROUP_to5, AGE_GROUP_6to18, AGE_GROUP_19to34, AGE_GROUP_35to49, AGE_GROUP_50to64, AGE_GROUP_65to
)
AS(
	SELECT *
	FROM(
		SELECT DRUG_NAME
			, CASE WHEN AGE<=5 THEN 'AGE_GROUP_to5'
				WHEN AGE<=18 THEN 'AGE_GROUP_6to18'
				WHEN AGE<=34 THEN 'AGE_GROUP_19to34'
				WHEN AGE<=49 THEN 'AGE_GROUP_35to49'
				WHEN AGE<=64 THEN 'AGE_GROUP_50to64'
				ELSE 'AGE_GROUP_65to'
			END AGE_GROUP
		FROM AGE
	) A
	PIVOT(
		COUNT(AGE_GROUP) FOR AGE_GROUP IN (AGE_GROUP_to5,AGE_GROUP_6to18,AGE_GROUP_19to34,AGE_GROUP_35to49,AGE_GROUP_50to64,AGE_GROUP_65to)
	) PV
),
N_FEMALE(
	DRUG_NAME, N_FEMALE
)
AS(
	SELECT A.DRUG_NAME, COUNT(*) N_FEMALE
	FROM CASES A
		INNER JOIN (
			SELECT PERSON_ID, GENDER_CONCEPT_ID
			FROM[SCAN].[DBO].PERSON
			WHERE GENDER_CONCEPT_ID IN (8532)
		) B
		ON A.PERSON_ID=B.PERSON_ID
	GROUP BY A.DRUG_NAME
)
SELECT A.DRUG_NAME, A.N_CASES, B.N_PRESCRIPTIONS
	, C.AGE_AVG, C.AGE_STDEV, AGE_GROUP_to5, D.AGE_GROUP_6to18, D.AGE_GROUP_19to34, D.AGE_GROUP_35to49, D.AGE_GROUP_50to64, D.AGE_GROUP_65to
	, E.N_FEMALE
INTO DEMOGRAPHICS
FROM N_CASES A
	INNER JOIN N_PRESCRIPTIONS B
	ON A.DRUG_NAME=B.DRUG_NAME
	INNER JOIN AGE_AVG C
	ON A.DRUG_NAME=C.DRUG_NAME
	INNER JOIN AGE_GROUP D
	ON A.DRUG_NAME=D.DRUG_NAME
	INNER JOIN N_FEMALE E
	ON A.DRUG_NAME=E.DRUG_NAME

-- Summary result
IF OBJECT_ID('[SJ_CERT_CDM4].[dbo].SUMMARY', 'U') IS NOT NULL
	DROP TABLE SUMMARY;
SELECT PERSON_ID, DRUG_NAME, LAB_NAME, OBSERVATION_CONCEPT_ID, ABNORM_TYPE
	, RANGE_LOW, RANGE_HIGH, RESULT_BEFORE=Y, RESULT_AFTER=N, RESULT_TYPE
	,CASE WHEN RESULT_TYPE IN ('MAX') AND Y<RANGE_HIGH THEN 'NORMAL'
		WHEN RESULT_TYPE IN ('MIN') AND Y>RANGE_LOW THEN 'NORMAL'
		ELSE 'ABNORMAL'
	END JUDGE_BEFORE
	,CASE WHEN RESULT_TYPE IN ('MAX') AND N<RANGE_HIGH THEN 'NORMAL'
		WHEN RESULT_TYPE IN ('MIN') AND N>RANGE_LOW THEN 'NORMAL'
		ELSE 'ABNORMAL'
	END JUDGE_AFTER
INTO SUMMARY
FROM(
	SELECT *
	FROM(
		SELECT *, 'MAX' RESULT_TYPE
		FROM CERT_EXPOSURE
		WHERE ABNORM_TYPE IN ('HYPER','BOTH')
	) A
	PIVOT(
		MAX(RESULT) FOR IS_BEFORE IN (Y,N)
	) PV
	UNION
	SELECT *
	FROM(
		SELECT *, 'MIN' RESULT_TYPE
		FROM CERT_EXPOSURE
		WHERE ABNORM_TYPE IN ('HYPO','BOTH')
	) A
	PIVOT(
		MIN(RESULT) FOR IS_BEFORE IN (Y,N)
	) PV
) T

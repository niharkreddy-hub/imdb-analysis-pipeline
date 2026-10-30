-- Entirely synthetic test data. These are not IMDb findings or portfolio results.
INSERT INTO staging.title_basics
SELECT 'tt'||i, 'movie', CASE WHEN i=1 THEN 'A "quoted" title' ELSE 'Movie '||i END,
       'Original '||i, '0', (2000+i)::TEXT, '\N', '90', 'Drama,Comedy,Drama'
FROM generate_series(1,5) i;
INSERT INTO staging.title_basics VALUES
('tt6','movie','Unrated title','Unrated title','0',NULL,NULL,NULL,NULL),
('tt100','tvSeries','Same Show','Same Show','0','2000',NULL,NULL,'Drama'),
('tt200','tvSeries','Same Show','Same Show','0','2010',NULL,NULL,'Drama'),
('tt101','tvEpisode','First A','First A','0','2000',NULL,'40','Drama'),
('tt201','tvEpisode','First B','First B','0','2010',NULL,'40','Drama'),
('tt102','tvEpisode','Special','Special','0','2000',NULL,'40','Drama'),
('tt103','tvEpisode','Season Three','Season Three','0','2002',NULL,'40','Drama'),
('tt104','tvEpisode','Season Five','Season Five','0','2004',NULL,'40','Drama'),
('tt900','movie','Bad adult','Bad','2020','2000',NULL,'90','Drama'),
('tt901','movie','Bad year','Bad','0','999999999999',NULL,'90','Drama'),
('tt902','movie','Bad runtime','Bad','0','2000',NULL,'999999999999','Drama'),
('tt903','movie','Future type','Bad','0','2000',NULL,'90','Drama');
UPDATE staging.title_basics SET title_type='futureType' WHERE tconst='tt903';

INSERT INTO staging.name_basics VALUES
('nm1','Person One','1970','\N','actor,director,director','tt1,tt2,tt999'),
('nm2','Person Two',NULL,NULL,'writer','tt1'),
('nm3','NA',NULL,NULL,'actress','tt2'),
('nm900','Invalid Year','999999999999',NULL,'actor',NULL);
INSERT INTO staging.title_crew
SELECT 'tt'||i, 'nm1,nm1', 'nm2' FROM generate_series(1,5) i;
INSERT INTO staging.title_crew VALUES ('tt100','nm999','\N'),('tt999','nm1',NULL);
INSERT INTO staging.title_ratings
SELECT 'tt'||i, (i+3)::TEXT, (i*50000)::TEXT FROM generate_series(1,5) i;
INSERT INTO staging.title_ratings VALUES
('tt100','9.0','100000'),('tt200','8.0','100000'),
('tt101','10.0','1000'),('tt201','2.0','1000'),('tt102','1.0','1000'),
('tt103','8.0','1000'),('tt104','6.0','1000'),
('tt999','8.0','100'),('tt1','NaN','100'),('tt2','8.0','999999999999'),
('tt3','8.55','100');
INSERT INTO staging.title_episode VALUES
('tt101','tt100','1','1'),('tt201','tt200','1','1'),('tt102','tt100','0','1'),
('tt103','tt100','3','1'),('tt104','tt100','5','1'),
('tt101','tt999','2','1'),('tt201','tt200','999999999999','1'),
('tt1','tt100','1','1');
INSERT INTO staging.title_principals
SELECT 'tt'||i, '1', 'nm1', 'actor', '\N', '["Character"]' FROM generate_series(1,5) i;
INSERT INTO staging.title_principals VALUES
('tt1','2','nm1','actor',NULL,'["Another character"]'),
('tt1','3','nm999','actor',NULL,NULL),
('tt1','4','nm2','writer',NULL,'not json'),
('tt1','5','nm2','writer',NULL,'{"not":"an array"}'),
('tt1','6','nm2','writer',NULL,'[1]'),
('tt1','7','nm2','writer',NULL,'["Quote: \"hello\""]');
INSERT INTO staging.title_akas VALUES
('tt1','1','A "quoted" title','AU','en','imdbDisplay'||chr(2)||'tv',NULL,'1'),
('tt2','1','A literal NA region','NA',NULL,NULL,NULL,'\N'),
('tt1','2','Invalid flag','US','en',NULL,NULL,'2');

(
echo 'DROP DATABASE wiaflos;'
echo 'CREATE DATABASE wiaflos;'
echo '\r wiaflos'
sed \
	-e 's/@PRELOAD@/SET FOREIGN_KEY_CHECKS=0;/' \
	-e 's/@POSTLOAD@/SET FOREIGN_KEY_CHECKS=1;/' \
	-e 's/@CREATE_TABLE_SUFFIX@/TYPE=InnoDB/' \
	-e 's/@SERIAL_TYPE@/SERIAL/' \
	-e 's/@BIG_INTEGER@/BIGINT UNSIGNED/' \
	-e 's/@SERIAL_REF_TYPE@/BIGINT UNSIGNED/'

) < schema.tsql
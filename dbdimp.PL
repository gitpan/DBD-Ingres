#!/usr/bin/perl
#
# This Perl-script does the cursor unrolling for dbdimp.sc
#
# Needed variables:
#     max_cursor =>  the number of simultaneouly open cursors
#
$max_cursor = $ARGV[0] || $ENV{MAX_CURSOR} || 9;

$rcs_id='$Id: dbdimp.PL,v 1.3 1996/12/03 08:11:55 ht Exp $';

open(OUT, ">dbdimp.sc") or die "Can't create dbdimp.sc\n";

print OUT <<'END_PART';
/*
 * $rcs_id
 *
 * Copyright (c) 1994,1995  Tim Bunce
 *           (c) 1996 Henrik Tougaard
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 *
 * This file is a copy of the oracle dbdimp.c, that has been mangled, cut
 * to shreds, thrown together and shamelessly mistreated, so that it can
 * have some (small) chance of success in the Ingres world.
 *
 * The blame for this abuse of Tim Bunce's good code lies solely on
 * me ht@datani.dk.
 * Ideas for cursor handling are stolen from DBD::Informix by
 * Alligator Descartes.
 *
 */


EXEC SQL INCLUDE 'Ingres.sh';

END_PART
print OUT <<END_PART;
#define MAX_CURSORS $max_cursor
static cursor cursors[MAX_CURSORS + 1];
END_PART
print OUT <<'END_PART';
DBISTATE_DECLARE;

int
sql_check(h)
    SV * h;
{
    EXEC SQL BEGIN DECLARE SECTION;
    char errbuf[256];
    EXEC SQL END DECLARE SECTION;
    D_imp_xxh(h);

    if (sqlca.sqlcode < 0) { 
        if (dbis->debug >= 3) 
            fprintf(DBILOGFP, "DBD::Ingres:sql_check: sqlcode=%d",
                    sqlca.sqlcode);
        sv_setiv(DBIc_ERR(imp_xxh), (IV)sqlca.sqlcode);
        if (dbis->debug >= 3) 
            fprintf(DBILOGFP, " get errtext");
        EXEC SQL INQUIRE_INGRES(:errbuf = ERRORTEXT);
        if (dbis->debug >= 3) 
            fprintf(DBILOGFP, " got errtext: '%s'", errbuf);
        sv_setpv(DBIc_ERRSTR(imp_xxh), (char*)errbuf);
        if (dbis->debug >= 3) 
            fprintf(DBILOGFP, ", returning\n");
        return 0;
    } else return 1;
}

void
error(h, error_num, text)
    SV * h;
    int error_num;
    char *text;
{
    D_imp_xxh(h);
    sv_setiv(DBIc_ERR(imp_xxh), (IV)error_num);
    sv_setpv(DBIc_ERRSTR(imp_xxh), (char*)text);
}

static int
new_cursor(h)
    SV * h;
{
    int i;
    
    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"Trying to get cursor\n");
        
    for (i = 0; i < MAX_CURSORS; ++i) {
        if (!cursors[i].is_open) {
            return i;
        }
    }
    error(h, -276, "All cursors in use already");
    return -1;
}

void
dbd_init(dbistate)
    dbistate_t *dbistate;
{
    DBIS = dbistate;
}

static char*
generate_statement_name()
{
    /* generates a (unique) statement name for each statement */
    /* I wonder if this is neccessary. We migth probably just */
    /* as well use the statement itself as name - or we could */
    /* use the cursor  number (or a function of it). The Ingres */
    /* documentation is extreemly weak here. */
    
    static char name[20];
    static int seed;
    sprintf(name, "stmt%12.12d", seed);
    return savepv(name);
}

void
fbh_dump(fbh, i)
    imp_fbh_t *fbh;
    int i;
{
    fprintf(DBILOGFP, "fbh_dump:");
    fprintf(DBILOGFP, "fbh %d: '%s' %s, ",
                i, fbh->var->sqlname.sqlnamec, (fbh->nullable) ? "NULLable" : "");
    fprintf(DBILOGFP, "type %d,  origlen %d, len %d\n",
            fbh->origtype, fbh->origlen, fbh->len);
    fprintf(DBILOGFP, "       VAR: type: %d, len: %d, ind: %p\n",
            fbh->var->sqltype, fbh->var->sqllen, fbh->var->sqlind);
}

int
dbd_rows(h)
    SV *h;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int rowcount;
    EXEC SQL END DECLARE SECTION;
    D_imp_xxh(h);
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "dbd_rows\n");
    EXEC SQL INQUIRE_INGRES(:rowcount = ROWCOUNT);
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "rowcount = %d\n", rowcount);
    if (!sql_check(h)) return -1;
    else return rowcount;
}

/* ================================================================== */

int
dbd_db_login(dbh, dbname, user, pass)
    SV *dbh;
    EXEC SQL BEGIN DECLARE SECTION;
    char *dbname;
    char *user;
    char *pass;
    EXEC SQL END DECLARE SECTION;
{
    D_imp_dbh(dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_login: database: %s\n", dbname);


    if (user && *user && *user != '/') {
        /* we have a username */
        if (dbis->debug >= 3) fprintf(DBILOGFP, "    user='%s', opt='%s'\n",
                                user, pass);
        EXEC SQL CONNECT :dbname IDENTIFIED BY :user OPTIONS = :pass;
    } else {
        /* just the databasename */
        if (dbis->debug >= 3) fprintf(DBILOGFP, "    nouser\n");
        EXEC SQL CONNECT :dbname OPTIONS = :pass;
    }
    if (dbis->debug >= 3) fprintf(DBILOGFP, "    After connect, sqlcode=%d\n",
                            sqlca.sqlcode);
    if (!sql_check(dbh)) return 0;
    DBIc_IMPSET_on(imp_dbh);    /* imp_dbh set up now                   */
    DBIc_ACTIVE_on(imp_dbh);    /* call disconnect before freeing       */
    return 1;
}

int
dbd_db_do(dbh, statement, attribs, params)
    SV * dbh;
    EXEC SQL BEGIN DECLARE SECTION;
    char * statement;
    EXEC SQL END DECLARE SECTION;
    char * attribs;
    SV *params;
{
    D_imp_dbh(dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_do(\"%s\")\n", statement);

    EXEC SQL EXECUTE IMMEDIATE :statement;
    if (!sql_check(dbh)) return -1;
    else return sqlca.sqlerrd[2]; /* rowcount */
}

int
dbd_db_commit(dbh)
    SV* dbh;
{
    D_imp_dbh(dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_commit\n");

    EXEC SQL COMMIT;
    return sql_check(dbh);
}

int
dbd_db_rollback(dbh)
    SV* dbh;
{ 
    D_imp_dbh(dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_rollback\n");

    EXEC SQL ROLLBACK;
    return sql_check(dbh);
}

int
dbd_db_disconnect(dbh)
    SV* dbh;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int transaction_active;
    EXEC SQL END DECLARE SECTION;
    D_imp_dbh(dbh);
    DBIc_ACTIVE_off(imp_dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_disconnect\n");

    EXEC SQL INQUIRE_INGRES(:transaction_active = TRANSACTION);
    if (transaction_active == 1){
        warn("Ingres: You should commit or rollback before disconnect.");
        warn("Ingres: Any outstanding changes have been rolledback.");
        EXEC SQL ROLLBACK;
        if (sqlca.sqlcode != 0) {
            warn("Ingres: problem rolling back");
        }
    }
    EXEC SQL DISCONNECT;
    /* We assume that disconnect will always work       */
    /* since most errors imply already disconnected.    */

    /* We don't free imp_dbh since a reference still exists	*/
    /* The DESTROY method is
     the only one to 'free' memory.     */
    return sql_check(dbh);
}

void
dbd_db_destroy(dbh)
    SV* dbh;
{
    D_imp_dbh(dbh);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_destroy\n");

    if (DBIc_ACTIVE(imp_dbh))
        dbd_db_disconnect(dbh);
    /* XXX free contents of imp_dbh */
    DBIc_IMPSET_off(imp_dbh);
}

int
dbd_db_STORE(dbh, keysv, valuesv)
    SV *dbh;
    SV *keysv;
    SV *valuesv;
{
    D_imp_dbh(dbh);
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on = SvTRUE(valuesv);

    if (kl==10 && strEQ(key, "AutoCommit")){
        /* Ignore SvTRUE warning: '=' where '==' may have been intended. */
        if (on) {
            EXEC SQL SET AUTOCOMMIT ON;
        } else {
            EXEC SQL SET AUTOCOMMIT OFF;
        }
        if (!sql_check(dbh)) {
    	    /* XXX um, we can't return FALSE and true isn't acurate */
	        /* the best we can do is cache an undef	*/
            cachesv = &sv_undef;
        }
        cachesv = (on) ? &sv_yes : &sv_no;	/* cache new state */
    } else {
        return FALSE;
    }
    if (cachesv) /* cache value for later DBI 'quick' fetch? */
        hv_store((HV*)SvRV(dbh), key, kl, cachesv, 0);
    return TRUE;
}

SV *
dbd_db_FETCH(dbh, keysv)
    SV* dbh;
    SV* keysv;
{
    D_imp_dbh(dbh);
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    int i;
    SV *retsv = NULL;
    /* Default to caching results for DBI dispatch quick_FETCH  */
    int cacheit = TRUE;

    if (1) {    /* no attribs defined yet       */
        return Nullsv;
    }
    if (cacheit) { /* cache for next time (via DBI quick_FETCH) */
        hv_store((HV*)SvRV(dbh), key, kl, retsv, 0);
        SvREFCNT_inc(retsv);    /* so sv_2mortal won't free it  */
    }
    return sv_2mortal(retsv);
}


/* ================================================================== */

int
dbd_st_prepare(sth, statement)
    SV* sth;
    EXEC SQL BEGIN DECLARE SECTION;
    char *statement;
    EXEC SQL END DECLARE SECTION;
{
    IISQLDA* sqlda;
    EXEC SQL BEGIN DECLARE SECTION;
    char* name;
    EXEC SQL END DECLARE SECTION;
    D_imp_sth(sth);
    D_imp_dbh_from_sth;

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_prepare('%s')\n", statement);

    imp_sth->done_desc = 0;
    sqlda = &imp_sth->sqlda;
    sqlda->sqln = IISQ_MAX_COLS;
    name = imp_sth->name = generate_statement_name();
    
    if (dbis->debug >= 3)
        fprintf(DBILOGFP,
            "DBD::Ingres::dbd_st_prepare statement('%s') name is %s, sqlda: %p\n",
            statement, name, sqlda);

    EXEC SQL PREPARE :name INTO sqlda FROM :statement;
    if (!sql_check(sth)) return 0;

    if (sqlda->sqld > sqlda->sqln) {
        /* too many cols returned - unlikely */
        croak("Ingres: Statement returns %d columns, max allowed is %d\n",
                sqlda->sqld, sqlda->sqln);
    }
    imp_sth->fbh_num = sqlda->sqld;
    imp_sth->row_num = 0;
    imp_sth->cursoridx = -1; /* unknown */
    DBIc_NUM_FIELDS(imp_sth) = imp_sth->fbh_num;

    if (dbis->debug >= 2)
        printf("DBD::Ingres::dbd_st_prepare: imp_sth->fbh_num: %d\n",
                imp_sth->fbh_num);

    DBIc_IMPSET_on(imp_sth);
    return 1;
}

int
dbd_describe(h, imp_sth)
     SV *h;
     imp_sth_t *imp_sth;
{
    IISQLDA* sqlda = &imp_sth->sqlda;
    int i;
    
    if (dbis->debug >= 2)
        fprintf(DBILOGFP,
            "DBD::Ingres::dbd_describe(name: %s)\n", imp_sth->name);

    if (imp_sth->done_desc) {
      if (dbis->debug >= 3) 
          fprintf(DBILOGFP,
            "In: DBD::Ingres::dbd_describe() done_desc = true\n");
      return 1; /* success, already done it */
    }
    imp_sth->done_desc = 1;

    /* describe the statement and allocate bufferspace */
    Newz(42, imp_sth->fbh, imp_sth->fbh_num + 1, imp_fbh_t);
    for (i = 0; i < sqlda->sqld; i++)
    {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var = &sqlda->sqlvar[i];
        fbh->nullable = var->sqltype < 0;
        fbh->origtype = var->sqltype = abs(var->sqltype);
        fbh->origlen = var->sqllen;
        var->sqlname.sqlnamec[var->sqlname.sqlnamel] = 0;
        
        if (dbis->debug >= 3)
            fprintf(DBILOGFP, "  field %d, type=%d\n", 1, var->sqltype);
            
        switch (var->sqltype) {
        case IISQ_INT_TYPE:
            fbh->len = var->sqllen = sizeof(int);
            strcpy(fbh->type, "d");
            /*Newc(42, var->sqldata, 1, long, char);*/
            Newz(42, fbh->var_ptr.iv, 1, int);
            var->sqldata = (char*)fbh->var_ptr.iv;
            fbh->sv = NULL;
            break;
        case IISQ_MNY_TYPE: /* money - treat as float8 */
        case IISQ_FLT_TYPE:
            fbh->len = var->sqllen = sizeof(double);
            var->sqltype = IISQ_FLT_TYPE;
            strcpy(fbh->type, "f");
            /*Newc(42, var->sqldata, 1, double, char);*/
            Newz(42, fbh->var_ptr.nv, 1, double);
            var->sqldata = (char*)fbh->var_ptr.nv;
            fbh->sv = NULL;
            break;
        case IISQ_DTE_TYPE:
            var->sqllen = IISQ_DTE_LEN;
            /* FALLTHROUGH */
        case IISQ_CHA_TYPE:
        case IISQ_VCH_TYPE:
        case IISQ_TXT_TYPE:
            var->sqltype = IISQ_CHA_TYPE;
            strcpy(fbh->type, "s");
            /* set up bufferspace */
            fbh->len = var->sqllen+1;
            fbh->sv = newSV((STRLEN)fbh->len);
            (void)SvUPGRADE(fbh->sv, SVt_PV);
            SvREADONLY_on(fbh->sv);
            (void)SvPOK_only(fbh->sv);
            var->sqldata = (char*)SvPVX(fbh->sv);
            fbh->var_ptr.pv = var->sqldata;
            break;
        default:        /* oh dear! */
            croak("Ingres: field %d has unsupported type %d\n",i+1,var->sqltype);
            break;
        }

        if (fbh->nullable) {
            var->sqlind = &fbh->indic;
            var->sqltype = - var->sqltype; /* changed sign indicates nullable */
        } else {
            var->sqlind = (short *)0;   /* no indicator variable*/
            fbh->indic = 0;             /* so that we can use this as an indicator variable later */
        }
        if (dbis->debug >= 2) {
            fprintf(DBILOGFP, "dumping it\n");
            fbh_dump(fbh, i);
        }
    } /* end allocation of field-data */

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_describe(%s) finished\n", imp_sth->name);

    return 1;
}

int
dbd_st_execute(sth)	/* <=0 is error, >0 is ok */
    SV *sth;
{
    D_imp_sth(sth);
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;
    
    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_execute(%s)\n", imp_sth->name);

    if (!imp_sth->done_desc) {
        /* describe and allocate storage for results		*/
        if (!dbd_describe(sth, imp_sth))
            return -1; /* dbd_describe already called sql_check()	*/
    }

    /* Trigger execution of the statement			*/
    if (imp_sth->fbh_num == 0) {
        /* non-select statement: just execute it */
        if (dbis->debug >= 2)
            fprintf(DBILOGFP,"DBD::Ingres::dbd_st_execute - non-select\n");

        EXEC SQL EXECUTE :name;
        return sql_check(sth) ? sqlca.sqlerrd[2] : -1;
    } else {
        /* select statement: open a cursor */
        int cursor_num = new_cursor(sth);
        if (cursor_num < 0) {
            return -1;
        }

        if (dbis->debug >= 2)
            fprintf(DBILOGFP,"DBD::Ingres::dbd_st_execute - cursor %d\n", cursor_num);

        imp_sth->cursoridx = cursor_num;
        /** Update cursor status in cursor array */
        cursors[cursor_num].is_open = 1;
        switch (cursor_num) {
END_PART
for $cursor (0..$max_cursor) {
print OUT <<END_LOOP;
        case $cursor:
            EXEC SQL DECLARE sql_cursor$cursor CURSOR FOR :name;
            EXEC SQL OPEN sql_cursor$cursor FOR READONLY;
            if (!sql_check(sth)) return -1;
            break;
END_LOOP
}
print OUT <<'END_PART';
        }
        DBIc_ACTIVE_on(imp_sth);
        return 0;
    }
}

AV *
dbd_st_fetchrow(sth)
    SV *	sth;
{
    IISQLDA* sqlda;
    D_imp_sth(sth);
    int num_fields;
    int i;
    AV *av;

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_fetchrow(%s)\n", imp_sth->name);

    if (!DBIc_ACTIVE(imp_sth)) {
        error(sth, -7, "fetch without open cursor");
        return Nullav;
    }
    sqlda = &imp_sth->sqlda;
    /*if (dbis->debug >= 3) {
    **    fprintf(DBILOGFP, "sqlda: %p\n", sqlda);
    **    for (i=0; i<imp_sth->fbh_num; i++) {
    **        imp_fbh_t *fbh = &imp_sth->fbh[i];
    **        fbh_dump(fbh, i);
    **    }
    **}*/
    
    switch(imp_sth->cursoridx) {
END_PART
for $cursor (0..$max_cursor) {
print OUT <<END_LOOP;
    case $cursor:
        EXEC SQL FETCH sql_cursor$cursor USING DESCRIPTOR :sqlda;
        break;
END_LOOP
}
print OUT <<'END_PART';
    }
    if (sqlca.sqlcode == 100) {
        return Nullav;
    } else
    if (!sql_check(sth)) return Nullav;

    /* Something was fetched, put the fields into the array */
    av = DBIS->get_fbav(imp_sth);
    num_fields = AvFILL(av)+1;

    if (dbis->debug >= 3)
        fprintf(DBILOGFP, "    dbd_st_fetchrow %d fields\n", num_fields);

    for(i=0; i < num_fields; ++i) {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var;
        SV *sv = AvARRAY(av)[i]; /* Note: we (re)use the SV in the AV	*/
        if (dbis->debug >= 3) fprintf(DBILOGFP, "    Field #%d: ", i);
        if (fbh->indic == -1) {
	        /* NULL value */
	        (void)SvOK_off(sv);
            if (dbis->debug >= 3) fprintf(DBILOGFP, "NULL\n");
	} else {
            switch (fbh->type[0]) {
            case 'd':
                sv_setsv(sv, newSViv((IV)*(int*)var->sqldata));
                if (dbis->debug >= 3)
                    fprintf(DBILOGFP, "Int: %ld %d %d\n", SvIV(sv), fbh->var_ptr.iv, *(int*)var->sqldata);
                break;
            case 'f':
                sv_setsv(sv, newSVnv(*(double*)var->sqldata));
                if (dbis->debug >= 3)
                    fprintf(DBILOGFP, "Double: %lf\n", SvNV(sv));
                break;
            case 's':
        	SvCUR(fbh->sv) = fbh->len;
        	SvPVX(fbh->sv)[fbh->len-1] = 0;
	        sv_setsv(sv, fbh->sv);
	        SvCUR(sv) = strlen(SvPVX(sv));
                if (dbis->debug >= 3)
                    fprintf(DBILOGFP, "Text: '%s'\n", SvPVX(sv));
	        break;
	    default:
	        croak("Ingres: wierd field-type '%s' in field no. %d?\n",
	                    fbh->type, i);
	        }
        }
    }
    if (dbis->debug >= 3) fprintf(DBILOGFP, "    End fetch\n");
    return av;
}

int
dbd_st_finish(sth)
    SV *sth;
{
    D_imp_sth(sth);
    /* Cancel further fetches from this cursor.                 */
    /* close the cursor - unlike Oracle, as there is no reason  */
    /* to reexecute it.. We won't do binds for a while yet..    */

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s)\n", imp_sth->name);

    if (DBIc_ACTIVE(imp_sth)) {
        int sqc = imp_sth->cursoridx;
        /* check if we have to close the cursor... */
        if (sqc >= 0 && sqc < MAX_CURSORS && cursors[sqc].is_open) {

            if (dbis->debug >= 3)
                fprintf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s), close cursor # %d\n",
                    imp_sth->name, imp_sth->cursoridx);

            switch (sqc) {
END_PART
for $cursor (0..$max_cursor) {
print OUT <<END_LOOP;
            case $cursor:
                EXEC SQL CLOSE sql_cursor$cursor;
                break;
END_LOOP
}
print OUT <<'END_PART';
            }
        cursors[sqc].is_open = 0;
        }
    }
    DBIc_ACTIVE_off(imp_sth);
    return 1;
}

void
dbd_st_destroy(sth)
    SV *sth;
{
    int i;
    D_imp_sth(sth);
    D_imp_dbh_from_sth;

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_destroy(%s)\n", imp_sth->name);

    /* XXX free contents of imp_sth here */
    DBIc_IMPSET_off(imp_sth);
}

int
dbd_st_STORE(sth, keysv, valuesv)
    SV *sth;
    SV *keysv;
    SV *valuesv;
{
    D_imp_sth(sth);
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on = SvTRUE(valuesv);

    if (dbis->debug >=3)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_STORE(%s)->{%s}\n", imp_sth->name, key);

    return FALSE; /* no values to store */
    
    if (cachesv) /* cache value for later DBI 'quick' fetch? */
        hv_store((HV*)SvRV(sth), key, kl, cachesv, 0);
    return TRUE;
}


SV *
dbd_st_FETCH(sth, keysv)
    SV *sth;
    SV *keysv;
{
    D_imp_sth(sth);
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    int i;
    SV *retsv = NULL;
    /* Default to caching results for DBI dispatch quick_FETCH  */
    int cacheit = TRUE;

    if (dbis->debug >= 3)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_FETCH(%s)->{%s}\n", imp_sth->name, key);

    if (!imp_sth->done_desc && !dbd_describe(sth, imp_sth)) {
        return Nullsv;  /* dbd_describe called sql_check()       */
    }

    i = imp_sth->fbh_num;

    if (kl==4 && strEQ(key, "TYPE")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].type, 0));
    } else if (kl==8 && strEQ(key, "NULLABLE")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, (imp_sth->fbh[i].nullable) ? &sv_yes : &sv_no);
    } else if (kl==6 && strEQ(key, "SqlLen")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origlen));
    } else if (kl==7 && strEQ(key, "SqlType")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origtype));
    } else if (kl==4 && strEQ(key, "NAME")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].var->sqlname.sqlnamec,
                        imp_sth->fbh[i].var->sqlname.sqlnamel));
    } else {
        return Nullsv;
    }
    if (cacheit) { /* cache for next time (via DBI quick_FETCH) */
        SV **svp = hv_fetch((HV*)SvRV(sth), key, kl, 1);
        sv_free(*svp);
        *svp = retsv; 

        /*hv_store((HV*)SvRV(sth), key, kl, retsv, 0); */
        (void)SvREFCNT_inc(retsv);      /* so sv_2mortal won't free it  */
    }
    return sv_2mortal(retsv);
}
END_PART

/*
 * $Id: dbdimp.sc,v 2.100 1997/09/10 08:00:41 ht000 Exp ht000 $
 *
 * Copyright (c) 1994,1995  Tim Bunce
 *           (c) 1996,1997  Henrik Tougaard
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
 *
 */


EXEC SQL INCLUDE 'Ingres.sh';

DBISTATE_DECLARE;
static int cur_session;    /* the 'current' Ingres session_id */
static int nxt_session;    /* the next 'available' session_id */

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
error(h, error_num, text, state)
    SV * h;
    int error_num;
    char * text;
    char * state;
{
    D_imp_xxh(h);
    sv_setiv(DBIc_ERR(imp_xxh), (IV)error_num);
    sv_setpv(DBIc_ERRSTR(imp_xxh), text);
    if (state != 0) sv_setpv(DBIc_STATE(imp_xxh), state);
}

void
set_session(h)
    SV * h;
{
    D_imp_dbh(h);
    EXEC SQL BEGIN DECLARE SECTION;
    int session_id = imp_dbh->session;
    EXEC SQL END DECLARE SECTION;
    if (cur_session != session_id) {
        if (dbis->debug >= 3)
            fprintf(DBILOGFP, "set session_db(%d)\n", session_id);
        EXEC SQL SET_SQL(SESSION = :session_id);
 	cur_session = session_id;
    }
}

void
dbd_init(dbistate)
    dbistate_t *dbistate;
{
    DBIS = dbistate;
    cur_session = 1;
    nxt_session = 1;
}

static U32* statement_numbers;    /* bitmask of reserved statement nos */
static int statement_max;         /* max bit number allocated (8 pr char) */

void release_statement(num)
    int num;
{
    if (num < 0 || num >= statement_max*8) return;
    statement_numbers[num/8] &= ~(1<<(num%8));
    if (dbis->debug >= 4)
	fprintf(DBILOGFP, "rel_st.nam: %d [%d]=%u\n", num, num/8,
	statement_numbers[num/8]);
}

static char*
generate_statement_name(st_num)
    int * st_num;
{
    /* find a (new) statement -name for this statement.
    ** Names can be reused when the statement handle is destroyed.
    ** The number of active statements is limited by the PSF in Ingres
    */    
    char name[20];
    int i, found=0, num;
    if (dbis->debug >= 4)
	fprintf(DBILOGFP, "gen_st.nam");
    for (i=0; i<statement_max; i++) {
        /* see if there is a free statement-name
           in the already allocated lump */
        int bit;
        if (dbis->debug >= 4)
	    fprintf(DBILOGFP, " [%d]=%u", i, statement_numbers[i]);
        for (bit=0; bit < 32; bit++) {
            if (((statement_numbers[i]>>bit) & 1) == 0) {
                /* free bit found */
                num = i*32+bit;
                found = 1;
                break;
            }
        }
        if (found) break;
    }
    if (!found) {
        /* allocate a new lump af numbers and take the first one */
        if (statement_max == 0) {
            /* first time round */
            if (dbis->debug >= 4)
	        fprintf(DBILOGFP, " alloc first time");
            num = 0;
            Newz(42, statement_numbers, 8, U32);
            for(i = statement_max; i <= statement_max+8; i++)
                statement_numbers[i] = 0;
            statement_max = 8;
        } else {
            num = statement_max * 32;
            if (dbis->debug >= 4)
	        fprintf(DBILOGFP, " alloc to %d", statement_max);
            Renew(statement_numbers, statement_max+8, U32);
            for(i = statement_max; i <= statement_max+8; i++)
                statement_numbers[i] = 0;
            statement_max += 8;
        }
    }
    statement_numbers[num/8] |= (1<<(num%8));
    sprintf(name, "stmt%12.12d", num);
    if (dbis->debug >= 4)
        fprintf(DBILOGFP, " returns %d\n", num);
    *st_num = num;
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
    EXEC SQL BEGIN DECLARE SECTION;
    int session;
    char * opt;
    EXEC SQL END DECLARE SECTION;

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_db_login: database: %s\n", dbname);

    session = imp_dbh->session = nxt_session++;

    opt = dbname;
    /* look for options in dbname. Syntax: dbname;options */
    while (*opt && *opt != ';') ++opt;
    if (*opt == ';') {
    	*opt = 0; /* terminate dbname */
    	++opt;    /* point to options */
    }
    
    if (user && *user && *user != '/') {
        /* we have a username */
        if (dbis->debug >= 3) fprintf(DBILOGFP, "    user='%s', opt='%s'\n",
                                user, opt);
	if (*pass) {
            EXEC SQL CONNECT :dbname SESSION :session
		 IDENTIFIED BY :user DBMS_PASSWORD=:pass OPTIONS=:opt;
	} else {
            EXEC SQL CONNECT :dbname SESSION :session
		 IDENTIFIED BY :user OPTIONS=:opt;
        }
    } else {
        /* just the databasename */
        if (dbis->debug >= 3) fprintf(DBILOGFP, "    nouser\n");
        EXEC SQL CONNECT :dbname SESSION :session OPTIONS = :opt;
    }
    if (dbis->debug >= 3)
	fprintf(DBILOGFP, "    After connect, sqlcode=%d, session=%d\n",
                            sqlca.sqlcode, imp_dbh->session);
    cur_session = imp_dbh->session;
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
    set_session(dbh);
    
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

    set_session(dbh);
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

    set_session(dbh);
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

    set_session(dbh);
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
dbd_db_STORE_attrib(dbh, keysv, valuesv)
    SV *dbh;
    SV *keysv;
    SV *valuesv;
{
    D_imp_dbh(dbh);
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on = SvTRUE(valuesv);

    set_session(dbh);
    if (kl==10 && strEQ(key, "AutoCommit")){
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
dbd_db_FETCH_attrib(dbh, keysv)
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

    set_session(dbh);
    if (kl==10 && strEQ(key, "AutoCommit")){
        EXEC SQL BEGIN DECLARE SECTION;
        int autocommit_state;
        EXEC SQL END DECLARE SECTION;
        
	EXEC SQL SELECT(DBMSINFO('autocommit_state'))
	    INTO :autocommit_state;
	return newSViv((IV)autocommit_state);
    } else {
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
dbd_st_prepare(sth, statement, attribs)
    SV* sth;
    EXEC SQL BEGIN DECLARE SECTION;
    char *statement;
    EXEC SQL END DECLARE SECTION;
    SV* attribs;   /* unused */
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
    name = imp_sth->name = generate_statement_name(&imp_sth->st_num);
    
    if (dbis->debug >= 3)
        fprintf(DBILOGFP,
            "DBD::Ingres::dbd_st_prepare statement('%s') name is %s, sqlda: %p\n",
            statement, name, sqlda);

    set_session(DBIc_PARENT_H(imp_sth));
    EXEC SQL PREPARE :name INTO sqlda FROM :statement;
    if (!sql_check(sth)) return 0;

    if (sqlda->sqld > sqlda->sqln) {
        /* too many cols returned - unlikely */
        croak("Ingres: Statement returns %d columns, max allowed is %d\n",
                sqlda->sqld, sqlda->sqln);
    }
    DBIc_NUM_FIELDS(imp_sth) = sqlda->sqld;

    /* See if there are any placeholders in the statement */
    {
    	char *src = statement;
    	int in_literal = 0;
    	int in_string = 0;
        int in_comment = 0;
        while(*src) {
	    if (*src == '"' && !in_string && !in_comment)
	        in_literal = ~in_literal;
	    else if (*src == '\'' && !in_literal && !in_comment)
	        in_string = ~in_string;
            else if (*src == '/' && src[1] == '*' && !in_literal && !in_string)
                in_comment = 1;
            else if (in_comment && *src == '*' && src[1] == '/')
                in_comment = 0;
	    if ((*src == '?') && !in_literal && !in_string && !in_comment)
	    	++DBIc_NUM_PARAMS(imp_sth);
	    ++src;
        }
    }
    if (dbis->debug >= 2)
        printf("DBD::Ingres::dbd_st_prepare: fields: %d, phs: %d\n",
                DBIc_NUM_FIELDS(imp_sth), DBIc_NUM_PARAMS(imp_sth));

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
    Newz(42, imp_sth->fbh, DBIc_NUM_FIELDS(imp_sth) + 1, imp_fbh_t);
    for (i = 0; i < sqlda->sqld; i++)
    {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var = &sqlda->sqlvar[i];
        /* fbh->nullable = var->sqltype < 0;
        ** Temporary hack for OpenIngres 1.2
        ** Can't determine nullability for outerjoins */
        fbh->nullable = 1;
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
dbd_bind_ph (sth, imp_sth, param, value, sql_type, attribs, is_inout, maxlen)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *param;
    SV *value;
    IV sql_type;
    SV *attribs;
    int is_inout;
    IV maxlen;
{
    int param_no;
    int type = 0;  /* 1: int, 2: float, 3: string */
    IISQLVAR* var;

    if (SvNIOK(param) ) {	/* passed as a number	*/
	param_no = (int)SvIV(param);
    } else {
	croak("bind_param: parameter not a number");
    }

    if (param_no < 1 || param_no > DBIc_NUM_PARAMS(imp_sth))
    	croak("Ingres(bind_param): parameter outside range 1..%d",
    		DBIc_NUM_PARAMS(imp_sth));

    if (imp_sth->ph_sqlda.sqld < param_no)
        imp_sth->ph_sqlda.sqld = param_no;

    var = &imp_sth->ph_sqlda.sqlvar[param_no-1];
    if (sql_type) {
    	switch (sql_type) {
	case SQL_INTEGER:
	case SQL_SMALLINT:
	    type = 1; break;
	case SQL_FLOAT:
	case SQL_REAL:
	case SQL_DOUBLE:
	case SQL_NUMERIC:
	case SQL_DECIMAL:
	    type = 2; break;
	case SQL_CHAR:
	case SQL_VARCHAR:
	    type = 3; break;
	}
    } else if (!SvOK(value)) { /* NULL */
	croak("Ingres(bind_param): sorry NULLs not allowed unless TYPE defined");
    } else if (SvIOK(value)) { /* integer */
	type = 1;
    } else if (SvNOK(value)) { /* float */
        type = 2;
    } else { /* char */
        type = 3;
    }
    switch (type) {
    case 1: {/* int */
    	int* ptr;
        var->sqlind = 0;
        var->sqllen = 4;
        Newz(42, ptr, 1, int);
	*ptr = (int)SvIV(value);
        var->sqldata = (char*)ptr;
        var->sqltype = IISQ_INT_TYPE;
	break; }
    case 2: {/* float */
	double* ptr;
        var->sqlind = 0;
        var->sqllen = 8;
        Newz(42, ptr, 1, double);
	*ptr = (double)SvNV(value);
        var->sqldata = (char*)ptr;
        var->sqltype = IISQ_FLT_TYPE;
        break; }
    case 3: {/* string */
        var->sqlind = 0;
        var->sqldata = savepv(SvPV(value, na));
        var->sqllen = strlen(var->sqldata);
        var->sqltype = IISQ_INT_TYPE;
        break; }
    }
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
        fprintf(DBILOGFP, "DBD::Ingres::dbd_st_execute(%s)\n", imp_sth->name);

    if (!imp_sth->done_desc) {
        /* describe and allocate storage for results		*/
        if (!dbd_describe(sth, imp_sth))
            return -1; /* dbd_describe already called sql_check()	*/
    }

    /* Trigger execution of the statement			*/
    set_session(DBIc_PARENT_H(imp_sth));
    if (DBIc_NUM_FIELDS(imp_sth) == 0) {
        /* non-select statement: just execute it */
        if (dbis->debug >= 2)
            fprintf(DBILOGFP,
                "DBD::Ingres::dbd_st_execute - non-select, param=%d\n",
                imp_sth->ph_sqlda.sqld);

        if (imp_sth->ph_sqlda.sqld > 0) {
            EXEC SQL EXECUTE :name USING DESCRIPTOR &imp_sth->ph_sqlda;
        } else {
            EXEC SQL EXECUTE :name;
        }
        return sql_check(sth) ? sqlca.sqlerrd[2] : -1;
    } else {
        /* select statement: open a cursor */
        if (dbis->debug >= 2)
            fprintf(DBILOGFP,
                "DBD::Ingres::dbd_st_execute - cursor %s - param=%d\n",
                name, imp_sth->ph_sqlda.sqld);

        EXEC SQL DECLARE :name CURSOR FOR :name;
        if (imp_sth->ph_sqlda.sqld > 0) {
            EXEC SQL OPEN :name FOR READONLY USING DESCRIPTOR &imp_sth->ph_sqlda;
        } else {
            EXEC SQL OPEN :name FOR READONLY;
        }
        if (!sql_check(sth)) return -1;
        DBIc_ACTIVE_on(imp_sth);
        return 0;
    }
}

AV *
dbd_st_fetch(sth)
    SV *     sth;
{
    IISQLDA* sqlda;
    D_imp_sth(sth);
    int num_fields;
    int i;
    AV *av;
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_fetch(%s)\n", imp_sth->name);

    if (!DBIc_ACTIVE(imp_sth)) {
        error(sth, -7, "fetch without open cursor", 0);
        return Nullav;
    }
    set_session(DBIc_PARENT_H(imp_sth));
    sqlda = &imp_sth->sqlda;
    EXEC SQL FETCH :name USING DESCRIPTOR :sqlda;
    if (sqlca.sqlcode == 100) {
        return Nullav;
    } else
    if (!sql_check(sth)) return Nullav;

    /* Something was fetched, put the fields into the array */
    av = DBIS->get_fbav(imp_sth);
    num_fields = AvFILL(av)+1;

    if (dbis->debug >= 3)
        fprintf(DBILOGFP, "    dbd_st_fetch %d fields\n", num_fields);

    for(i=0; i < num_fields; ++i) {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var;
        int ch;
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
        	/* strip trailing blanks */
        	if (fbh->origtype == IISQ_CHA_TYPE
                 && DBIc_on(imp_sth, DBIcf_ChopBlanks)) {
        	    for (ch = fbh->len - 2;
        	         SvPVX(fbh->sv)[ch] == ' ';
        	         --ch)
        	             SvPVX(fbh->sv)[ch] = 0;
        	}
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
dbd_st_rows(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int rowcount;
    EXEC SQL END DECLARE SECTION;
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "dbd_rows\n");
    set_session(DBIc_PARENT_H(imp_sth));
    EXEC SQL INQUIRE_INGRES(:rowcount = ROWCOUNT);
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "rowcount = %d\n", rowcount);
    if (!sql_check(sth)) return -1;
    else return rowcount;
}

int
dbd_st_finish(sth)
    SV *sth;
{
    D_imp_sth(sth);
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;
    
    /* Cancel further fetches from this cursor.                 */
    if (DBIc_ACTIVE(imp_sth)) {
        if (dbis->debug >= 3)
            fprintf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s)\n",
                imp_sth->name);
        set_session(DBIc_PARENT_H(imp_sth));
        EXEC SQL CLOSE :name;
    }
    DBIc_ACTIVE_off(imp_sth);

    if (dbis->debug >= 2)
        fprintf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s)\n", imp_sth->name);

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

    release_statement(imp_sth->st_num);
     
    /* XXX free contents of imp_sth here */
    DBIc_IMPSET_off(imp_sth);
}

int
dbd_st_STORE_attrib(sth, keysv, valuesv)
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
dbd_st_FETCH_attrib(sth, keysv)
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
        fprintf(DBILOGFP, "DBD::Ingres::dbd_st_FETCH(%s)->{%s}\n",
                imp_sth->name, key);

    if (kl==10 && strEQ(key, "CursorName")) {
	return newSVpv(imp_sth->name, 0);	
    }

    if (!imp_sth->done_desc && !dbd_describe(sth, imp_sth)) {
        /* dbd_describe called sql_check()       */
	/* we can't return Nullsv here because the xs code will	*/
	/* then just pass the attribute name to DBI for FETCH.	*/
	croak("Describe failed during %s->FETCH(%s)",
		SvPV(sth, na), key);
    }

    i = DBIc_NUM_FIELDS(imp_sth);

    if (kl==8 && strEQ(key, "ing_type")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].type, 0));
    } else if (kl==4 && strEQ(key, "TYPE")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0) {
            int type;
            switch (imp_sth->fbh[i].origtype) {
            case IISQ_INT_TYPE:
		type = SQL_INTEGER;
		break;
            case IISQ_MNY_TYPE:
                type = SQL_DECIMAL;
                break;
            case IISQ_FLT_TYPE:
                type = SQL_FLOAT;
                break;
            case IISQ_DTE_TYPE:
            case IISQ_CHA_TYPE:
            case IISQ_VCH_TYPE:
            case IISQ_TXT_TYPE:
                type = SQL_CHAR;
                break;
            default:        /* oh dear! */
                type = 0;
                break;
            }
            av_store(av, i, newSViv(type));
        }
    } else if (kl==8 && strEQ(key, "NULLABLE")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, (imp_sth->fbh[i].nullable) ? &sv_yes : &sv_no);
    } else if (kl==4 && strEQ(key, "NAME")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].var->sqlname.sqlnamec,
                        imp_sth->fbh[i].var->sqlname.sqlnamel));
    } else if (kl==11 && strEQ(key, "ing_lengths") ||
               kl==6 && strEQ(key, "SqlLen")){
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origlen));
    } else if ((kl==9 && strEQ(key, "ing_types")) ||
               (kl==12 && strEQ(key, "ing_ingtypes")) ||
               (kl==7 && strEQ(key, "SqlType")) ) {
        AV *av = newAV();
        retsv = newRV((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origtype));
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

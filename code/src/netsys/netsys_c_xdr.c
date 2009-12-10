/* $Id$ */

/* Some helpers for en/decoding XDR faster */

#include "netsys_c.h"
#ifndef _WIN32
#include <arpa/inet.h>
#endif

extern value **caml_ref_table_ptr;

CAMLprim value netsys_s_read_int4_64(value sv, value pv) 
{
    char *s;
    long p;

    s = String_val(sv);
    p = Long_val(pv);
    return Val_long((long) (ntohl (*((unsigned int *) (s+p)))));
}

CAMLprim value netsys_s_write_int4_64(value sv, value pv, value iv) 
{
    char *s;
    long p;

    s = String_val(sv);
    p = Long_val(pv);
    *((unsigned int *) (s+p)) = htonl ((unsigned int) Long_val(iv));
    return Val_unit;
}


static value netsys_alloc_string_shr(mlsize_t len)
{
    /* Always allocate in major heap */
    value result;
    mlsize_t offset_index;
    mlsize_t wosize = (len + sizeof (value)) / sizeof (value);

    result = caml_alloc_shr (wosize, String_tag);
    result = caml_check_urgent_gc (result);

    Field (result, wosize - 1) = 0;
    offset_index = Bsize_wsize (wosize) - 1;
    Byte (result, offset_index) = offset_index - len;
    return result;
}


CAMLprim value netsys_s_read_string_array(value sv, value pv, value lv,
					  value mv, value av)
{
    char *s;
    long p, l, n, k;
    unsigned int e, j, m;
    value uv;
    int av_in_heap;
    int err;
    value r;
    value **old_reftbl;
    CAMLparam2(sv,av);

    s = String_val(sv);  /* will have to redo after each allocation */
    p = Long_val(pv);
    l = Long_val(lv) + p;
    m = (unsigned int) Int32_val(mv);
    n = Wosize_val(av);
    av_in_heap = 0;
    /* If av is already in the major heap, it is an extra burden to allocate
       the new string in the minor heap. The new string would be a local
       root until the next minor collection. We avoid this by allocating the
       new string in the major heap directly if av is already there.

       we don't have access to the Is_in_heap macro, so watch for changing
       caml_ref_table_ptr
    */

    err = 0;
    k = 0;
    while (k < n) {
	if (p+4 > l) break;
	e = ntohl(*((unsigned int *) (s+p)));
	p += 4;
	j = l-p;
	if (e > j) { err=-1; break; }
	if (e > m) { err=-2; break; }
	uv = av_in_heap ? netsys_alloc_string_shr(e) : caml_alloc_string(e);
	s = String_val(sv);           /* see above */
	memcpy(String_val(uv), s+p, e);
	/* old_reftbl = caml_ref_table_ptr; */
	caml_modify(&Field(av,k), uv);
	/* if (old_reftbl != caml_ref_table_ptr) av_in_heap = 1; */
	p += e;
	if ((e&3) != 0) p += 4-(e&3);
	k++;
    }

    r = Val_long(err);
    if (k >= n) r = Val_long(p);
    CAMLreturn(r);
}

TOP_DIR = ../../..
include $(TOP_DIR)/Makefile.rules
include $(TOP_DIR)/Makefile.xrules

XDRFILES = proto.x

RPCGEN_AUX_OPTIONS    = -int int32 -hyper int64
RPCGEN_CLIENT_OPTIONS = -int int32 -hyper int64
RPCGEN_SERVER_OPTIONS = -int int32 -hyper int64

CLEAN_LIST += socket protosettings protoclient protoserver \
	      *.astamp *.cstamp *.s2stamp \
	      proto_aux.ml proto_aux.mli \
	      proto_clnt.ml proto_clnt.mli \
	      proto_srv.ml proto_srv.mli

all:
	$(MAKE) gen
	$(MAKE) depend
	$(MAKE) -f Makefile.code all

opt:
	$(MAKE) gen
	$(MAKE) depend
	$(MAKE) -f Makefile.code opt

build: all

BENCH_ARGS?=all

test:
	./prototest $(BENCH_ARGS)

gen: $(XDRFILES:.x=.astamp) $(XDRFILES:.x=.cstamp) $(XDRFILES:.x=.s2stamp)

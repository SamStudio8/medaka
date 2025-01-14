.PHONY: docs clean_samtools wheels sdist

# Builds a cache of binaries which can just be copied for CI
BINARIES=samtools minimap2 tabix bgzip
BINCACHEDIR=bincache
$(BINCACHEDIR):
	mkdir -p $(BINCACHEDIR)
OS := $(shell uname)
ifeq ($(OS), Darwin)
SEDI=sed -i '.bak'
else
SEDI=sed -i
endif

binaries: $(addprefix $(BINCACHEDIR)/, $(BINARIES))

SAMVER=1.9
submodules/samtools-$(SAMVER)/Makefile:
	cd submodules; \
		curl -L -o samtools-${SAMVER}.tar.bz2 https://github.com/samtools/samtools/releases/download/${SAMVER}/samtools-${SAMVER}.tar.bz2; \
		tar -xjf samtools-${SAMVER}.tar.bz2; \
		rm samtools-${SAMVER}.tar.bz2


libhts.a: submodules/samtools-$(SAMVER)/Makefile
	# this is required only to add in -fpic so we can build python module
	@echo Compiling $(@F)
	cd submodules/samtools-${SAMVER}/htslib-${SAMVER}/ && CFLAGS=-fpic ./configure && make
	cp submodules/samtools-${SAMVER}/htslib-${SAMVER}/$@ $@


$(BINCACHEDIR)/samtools: | libhts.a $(BINCACHEDIR)
	@echo Making $(@F)
	# copy our hack up version of tview
	${SEDI} 's/tv->is_dot = 1;/tv->is_dot = 0;/' submodules/samtools-${SAMVER}/bam_tview.c
	cd submodules/samtools-${SAMVER} && make -j 4
	cp submodules/samtools-${SAMVER}/$(@F) $@


$(BINCACHEDIR)/tabix: | libhts.a $(BINCACHEDIR)
	cp submodules/samtools-${SAMVER}/htslib-${SAMVER}/$(@F) $@


$(BINCACHEDIR)/bgzip: | libhts.a $(BINCACHEDIR)
	cp submodules/samtools-${SAMVER}/htslib-${SAMVER}/$(@F) $@


clean_htslib:
	cd submodules/samtools-${SAMVER} && make clean || exit 0
	cd submodules/samtools-${SAMVER}/htslib-${SAMVER} && make clean || exit 0


$(BINCACHEDIR)/minimap2: | $(BINCACHEDIR)
	@echo Making $(@F)
	curl -L -o minimap2-2.11_x64-linux.tar.bz2 https://github.com/lh3/minimap2/releases/download/v2.11/minimap2-2.11_x64-linux.tar.bz2 
	tar -xvf minimap2-2.11_x64-linux.tar.bz2
	cp minimap2-2.11_x64-linux/minimap2 $@
	rm -rf minimap2-2.11_x64-linux.tar.bz2 minimap2-2.11_x64-linux


$(BINCACHEDIR)/vcf2fasta: | $(BINCACHEDIR)
	cd src/vcf2fasta && g++ -std=c++11 \
		-I./../../submodules/samtools-${SAMVER}/htslib-${SAMVER}/ vcf2fasta.cpp \
		./../../submodules/samtools-${SAMVER}/htslib-${SAMVER}/libhts.a \
		-lz -llzma -lbz2 -lpthread \
		-o $(@F)
	cp src/vcf2fasta/$(@F) $@


scripts/mini_align:
	@echo Making $(@F)
	curl https://raw.githubusercontent.com/nanoporetech/pomoxis/master/scripts/mini_align -o $@
	chmod +x $@


venv: venv/bin/activate
IN_VENV=. ./venv/bin/activate

venv/bin/activate:
	test -d venv || virtualenv venv --python=python3 --prompt "(medaka) "
	${IN_VENV} && pip install pip --upgrade
	${IN_VENV} && pip install -r requirements.txt


install: venv scripts/mini_align libhts.a | $(addprefix $(BINCACHEDIR)/, $(BINARIES))
	${IN_VENV} && MEDAKA_BINARIES=1 python setup.py install


test: install
	${IN_VENV} && pip install nose
	${IN_VENV} && python setup.py nosetests


clean: clean_htslib
	(${IN_VENV} && python setup.py clean) || echo "Failed to run setup.py clean"
	rm -rf libhts.a libmedaka.abi3.so venv build dist/ medaka.egg-info/ __pycache__ medaka.egg-info
	find . -name '*.pyc' -delete


wheels:
	docker run -v `pwd`:/io quay.io/pypa/manylinux1_x86_64 /io/build-wheels.sh


build: pypi_build/bin/activate
IN_BUILD=. ./pypi_build/bin/activate
pypi_build/bin/activate:
	test -d pypi_build || virtualenv pypi_build --python=python3 --prompt "(pypi) "
	${IN_BUILD} && pip install pip --upgrade
	${IN_BUILD} && pip install --upgrade pip setuptools twine wheel readme_renderer[md]


sdist: pypi_build/bin/activate scripts/mini_align submodules/samtools-$(SAMVER)/Makefile
	${IN_BUILD} && python setup.py sdist


# Documentation
SPHINXOPTS    =
SPHINXBUILD   = sphinx-build
PAPER         =
BUILDDIR      = _build
PAPEROPT_a4     = -D latex_paper_size=a4
PAPEROPT_letter = -D latex_paper_size=letter
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) .
DOCSRC = docs

docs: venv
	${IN_VENV} && pip install sphinx sphinx_rtd_theme sphinx-argparse
	${IN_VENV} && cd $(DOCSRC) && $(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
	rm -rf docs/modules.rst docs/medaka.rst  
	@echo
	@echo "Build finished. The HTML pages are in $(DOCSRC)/$(BUILDDIR)/html."
	touch $(DOCSRC)/$(BUILDDIR)/html/.nojekyll



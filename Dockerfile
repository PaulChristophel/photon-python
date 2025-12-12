FROM photon:5.0 AS python-base

# ensure local python is preferred over distribution python
ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8

ARG PYTHON_VERSION=3.11.14
ARG PYTHON_SHA256=8d3ed8ec5c88c1c95f5e558612a725450d2452813ddad5e58fdb1a53b1209b78

# runtime and build dependencies
RUN set -eux; \
	tdnf update -y; \
	tdnf install -y \
		build-essential \
		wget \
		gnupg \
		ca-certificates \
		xz \
		zlib \
		zlib-devel \
		bzip2-libs \
		bzip2-devel \
		openssl \
		openssl-devel \
		libffi \
		libffi-devel \
		sqlite-libs \
		sqlite-devel \
		readline \
		readline-devel \
		findutils \
		gdb \
	; \
	tdnf clean all; \
	rm -rf /var/cache/tdnf; \
	wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
	echo "$PYTHON_SHA256 *python.tar.xz" | sha256sum -c -; \
	mkdir -p /usr/src/python; \
	tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
	rm python.tar.xz; \
	\
	cd /usr/src/python; \
	arch="$(uname -m)"; \
	lto_flag="--with-lto"; \
	if [ "$arch" = "riscv64" ]; then lto_flag=""; fi; \
	ax_cv_c_float_words_bigendian=no ac_cv_c_bigendian=no ./configure \
		--enable-loadable-sqlite-extensions \
		--enable-optimizations \
		--enable-option-checking=fatal \
		--enable-shared \
		"$lto_flag" \
		--with-ensurepip \
	; \
	nproc="$(getconf _NPROCESSORS_ONLN || nproc)"; \
	make -j 1; \
	\
	# prevent accidental usage of a system installed libpython of the same version
	rm python; \
	make -j 1 \
		"LDFLAGS=${LDFLAGS:--Wl,-rpath='\$\$ORIGIN/../lib'}" \
		python \
	; \
	make install; \
	\
	# enable GDB to load debugging data
	bin="$(readlink -ve /usr/local/bin/python3)"; \
	dir="$(dirname "$bin")"; \
	mkdir -p "/usr/share/gdb/auto-load/$dir"; \
	cp -vL Tools/gdb/libpython.py "/usr/share/gdb/auto-load/$bin-gdb.py"; \
	\
	cd /; \
	rm -rf /usr/src/python; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
		\) -exec rm -rf '{}' + \
	; \
	\
	ldconfig; \
	\
	export PYTHONDONTWRITEBYTECODE=1; \
	python3 --version; \
	\
	pip3 install \
		--disable-pip-version-check \
		--no-cache-dir \
		--no-compile \
		'setuptools==79.0.1' \
		'wheel<0.46' \
	; \
	tdnf remove -y \
		build-essential \
		wget \
		gnupg \
		zlib-devel \
		bzip2-devel \
		openssl-devel \
		libffi-devel \
		sqlite-devel \
		readline-devel \
		gdb \
	; \
	pip3 --version

# make some useful symlinks that are expected to exist ("/usr/local/bin/python" and friends)
RUN set -eux; \
	for src in pip3 pydoc3 python3 python3-config; do \
		dst="$(echo "$src" | tr -d 3)"; \
		[ -s "/usr/local/bin/$src" ]; \
		[ ! -e "/usr/local/bin/$dst" ]; \
		ln -svT "$src" "/usr/local/bin/$dst"; \
	done

CMD ["python3"]

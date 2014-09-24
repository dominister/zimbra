%define apacheconfdir %{_sysconfdir}/httpd/conf.d
# this path is hardcoded
%define cblibdir %{_libdir}/policyd-cluebringer-2.0

%define version @PKG_VER_MAIN_CLEAN@
%define release 1

Summary: Email server policy daemon
Name: policyd-cluebringer
Version: %{version}
Release: %{release}
License: GPLv2
Group: System/Daemons
URL: http://www.policyd.org
Source0: http://downloads.policyd.org/%{version}/%{name}-%{version}.tar.bz2

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch

Provides: cbpolicyd = %{version}
Obsoletes: cbpolicyd

Provides: policyd = %{version}
Obsoletes: policyd

Requires: perl(Net::Server), perl(Config::IniFiles), perl(Cache::FastMmap), httpd


%description
PolicyD v2 (codenamed "cluebringer") is a multi-platform policy server
for popular MTAs. This policy daemon is designed mostly for large
scale mail hosting environments. The main goal is to implement as many
spam combating and email compliance features as possible while at the
same time maintaining the portability, stability and performance
required for mission critical email hosting of today. Most of the
ideas and methods implemented in PolicyD v2 stem from PolicyD v1
as well as the authors' long time involvement in large scale mail
hosting industry.


%prep
%setup -q -n %{name}-%{version}

# hack to prevent rpmbuild from automatically detecting "requirements" that
# aren't actually external requirements.  See https://fedoraproject.org/wiki/Packaging/Perl#In_.25prep_.28preferred.29
cat << EOF > %{name}-req
#!/bin/sh
%{__perl_requires} $* | sed -e '/perl(cbp::/d'
EOF

%define __perl_requires %{_builddir}/%{name}-%{version}/%{name}-req
chmod +x %{__perl_requires}


%build
cd database
for db_type in mysql4 mysql pgsql sqlite; do
	./convert-tsql ${db_type} core.tsql > policyd.${db_type}.sql
	for file in `find . -name \*.tsql -and -not -name core.tsql`; do
		./convert-tsql ${db_type} ${file}
	done >> policyd.${db_type}.sql
	cd whitelists
		./parse-checkhelo-whitelist >> policyd.${db_type}.sql
		./parse-greylisting-whitelist >> policyd.${db_type}.sql
	cd ..
done


%install
rm -rf $RPM_BUILD_ROOT


# cbpolicyd
mkdir -p $RPM_BUILD_ROOT%{cblibdir}
mkdir -p $RPM_BUILD_ROOT%{_sbindir}
mkdir -p $RPM_BUILD_ROOT%{_initrddir}
mkdir -p $RPM_BUILD_ROOT%{_localstatedir}/log/policyd-cluebringer
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/policyd-cluebringer
cp -R cbp $RPM_BUILD_ROOT%{cblibdir}
install -m 755 cbpolicyd cbpadmin $RPM_BUILD_ROOT%{_sbindir}
install -m 644 cluebringer.conf $RPM_BUILD_ROOT%{_sysconfdir}/policyd-cluebringer/cluebringer.conf
install -m 755 contrib/initscripts/Fedora/cbpolicyd $RPM_BUILD_ROOT%{_initrddir}

# Webui
mkdir -p $RPM_BUILD_ROOT%{_datadir}/policyd-cluebringer/webui
mkdir -p $RPM_BUILD_ROOT%{apacheconfdir}
cp -R webui/* $RPM_BUILD_ROOT%{_datadir}/policyd-cluebringer/webui/
install -m 644 contrib/httpd/cluebringer-httpd.conf $RPM_BUILD_ROOT%{apacheconfdir}/policyd-cluebringer.conf
# Move config into /etc
mv $RPM_BUILD_ROOT%{_datadir}/policyd-cluebringer/webui/includes/config.php $RPM_BUILD_ROOT%{_sysconfdir}/policyd-cluebringer/webui.conf
ln -s %{_sysconfdir}/policyd-cluebringer/webui.conf $RPM_BUILD_ROOT%{_datadir}/policyd-cluebringer/webui/includes/config.php
chmod 0640 $RPM_BUILD_ROOT%{_sysconfdir}/policyd-cluebringer/webui.conf

# Docdir
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/contrib
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/database
install -m 644 AUTHORS INSTALL LICENSE TODO WISHLIST ChangeLog $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}
cp -R contrib $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/contrib/amavisd-new
install -m 644 database/*.sql $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/database


%post
/sbin/chkconfig --add cbpolicyd


%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc %{_docdir}/%{name}-%{version}
%{cblibdir}/
%{_sbindir}/cbpolicyd
%{_sbindir}/cbpadmin
%{_initrddir}/cbpolicyd

%dir %{_datadir}/policyd-cluebringer
%attr(-,root,apache) %{_datadir}/policyd-cluebringer/webui/

%dir %{_sysconfdir}/policyd-cluebringer
%config(noreplace) %{_sysconfdir}/policyd-cluebringer/cluebringer.conf

%attr(-,root,apache) %config(noreplace) %{_sysconfdir}/policyd-cluebringer/webui.conf

%config(noreplace) %{apacheconfdir}/policyd-cluebringer.conf

%dir %{_localstatedir}/log/policyd-cluebringer

%changelog


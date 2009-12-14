%define apacheconfdir %{_sysconfdir}/httpd/conf.d
# this path is hardcoded
%define cblibdir %{_libdir}/policyd-2.0

%define version 2.0.9
%define release 1
%define tarver %{version}

Summary: Postfix Policy Daemon
Name: cluebringer
Version: %{version}
Release: %{release}
License: GPLv2
Group: System/Daemons
URL: http://www.policyd.org
Source0: http://downloads.sourceforge.net/policyd/%{name}-%{tarver}.tar.bz2

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch

Provides: cbpolicyd

Provides: policyd = %{version}
Obsoletes: policyd

Requires: perl(Net::Server), perl(Config::IniFiles), perl(Cache::FastMmap), httpd


%description
Policyd v2 (codenamed "cluebringer") is a multi-platform policy server
for popular MTAs. This policy daemon is designed mostly for large
scale mail hosting environments. The main goal is to implement as many
spam combating and email compliance features as possible while at the
same time maintaining the portability, stability and performance
required for mission critical email hosting of today. Most of the
ideas and methods implemented in Policyd v2 stem from Policyd v1
as well as the authors' long time involvement in large scale mail
hosting industry.


%prep
%setup -q -n %{name}-%{tarver}

# hack to prevent rpmbuild from automatically detecting "requirements" that
# aren't actually external requirements.  See https://fedoraproject.org/wiki/Packaging/Perl#In_.25prep_.28preferred.29
cat << EOF > %{name}-req
#!/bin/sh
%{__perl_requires} $* | sed -e '/perl(cbp::/d'
EOF

%define __perl_requires %{_builddir}/%{name}-%{tarver}/%{name}-req
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
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/policyd
cp -R cbp $RPM_BUILD_ROOT%{cblibdir}
install -m 755 cbpolicyd cbpadmin database/convert-tsql $RPM_BUILD_ROOT%{_sbindir}
install -m 644 cluebringer.conf $RPM_BUILD_ROOT%{_sysconfdir}/policyd/cluebringer.conf
install -m 755 contrib/initscripts/Fedora/cbpolicyd $RPM_BUILD_ROOT%{_initrddir}

# Webui
mkdir -p $RPM_BUILD_ROOT%{_datadir}/%{name}/webui
mkdir -p $RPM_BUILD_ROOT%{apacheconfdir}
cp -R webui/* $RPM_BUILD_ROOT%{_datadir}/%{name}/webui/
install -m 644 contrib/httpd/cluebringer-httpd.conf $RPM_BUILD_ROOT%{apacheconfdir}/cluebringer.conf
# Move config into /etc
mv $RPM_BUILD_ROOT%{_datadir}/%{name}/webui/includes/config.php $RPM_BUILD_ROOT%{_sysconfdir}/policyd/webui.conf
ln -s %{_sysconfdir}/policyd/webui.conf $RPM_BUILD_ROOT%{_datadir}/%{name}/webui/includes/config.php
chmod 0640 $RPM_BUILD_ROOT%{_sysconfdir}/policyd/webui.conf

# Docdir
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/contrib
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}/database
install -m 644 AUTHORS INSTALL LICENSE TODO WISHLIST CHANGELOG $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}
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
%{_sbindir}/convert-tsql
%{_initrddir}/cbpolicyd

%dir %{_datadir}/%{name}
%attr(-,root,apache) %{_datadir}/%{name}/webui/

%dir %{_sysconfdir}/policyd
%config(noreplace) %{_sysconfdir}/policyd/cluebringer.conf

%attr(-,root,apache) %config(noreplace) %{_sysconfdir}/policyd/webui.conf

%config(noreplace) %{apacheconfdir}/cluebringer.conf


%changelog
* Wed Oct 14 2009 Nigel Kukard  <nkukard@lbsd.net>
- 2.0.8 release

* Tue May 05 2009 Nigel Kukard  <nkukard@lbsd.net>
- 2.0.7 release

* Tue Jan 06 2009 Nigel Kukard  <nkukard@lbsd.net>
- 2.0.6 release

* Wed Nov 19 2008 Nigel Kukard  <nkukard@lbsd.net>
- Various updates and changes

* Tue Nov 18 2008 Christopher St Pierre <stpierre@NebrWesleyan.edu> - 
- Initial build.


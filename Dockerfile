FROM ubuntu:15.04

RUN apt-get update
RUN apt-get install -y cron build-essential zlib1g-dev ruby ruby-dev

RUN gem install bundler

ADD Gemfile Gemfile
ADD Gemfile.lock Gemfile.lock
RUN bundle install

ADD staticize.rb staticize.rb
ADD util.rb util.rb
ADD .env .env

ADD crontab /etc/cron.d/staticizer
RUN chmod 0644 /etc/cron.d/staticizer

RUN touch /var/log/staticizer.log

CMD cron && tail -f /var/log/staticizer.log

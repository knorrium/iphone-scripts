#!/usr/bin/env ruby

##
# appstore_reviews
#
#  Fetch iTunes App Store reviews for each application, across all country stores
#   -- reads rating, author, subject and review body
#
# Notes
#  Derived from Erica Sadun's scraper: http://blogs.oreilly.com/iphone/2008/08/scraping-appstore-reviews.html
#  Apple's XML is purely layout-based, without much semantic relation to reviews, so the CSS paths below
#   are brittle.
#
# Jeremy Wohl
#   relevant post: http://igmus.org/2008/09/fetching-app-store-reviews
#
# TODO: spider additional review pages
#

require 'rubygems'
require 'hpricot'
require 'httparty'
require 'csv'

# MODIFY THIS HASH WITH YOUR APP SET (grab the itunes store urls & pull the id params)
software = {
  # http://phobos.apple.com/WebObjects/MZStore.woa/wa/viewSoftware?id=289923007&mt=8
  'Domain Scout' => 289923007,
}

stores = [
  { :name => 'United States',        :id => 143441 },
  { :name => 'Argentina',            :id => 143505 },
  { :name => 'Australia',            :id => 143460 },
  { :name => 'Belgium',              :id => 143446 },
  { :name => 'Brazil',               :id => 143503 },
  { :name => 'Canada',               :id => 143455 },
  { :name => 'Chile',                :id => 143483 },
  { :name => 'China',                :id => 143465 },
  { :name => 'Colombia',             :id => 143501 },
  { :name => 'Costa Rica',           :id => 143495 },
  { :name => 'Croatia',              :id => 143494 },
  { :name => 'Czech Republic',       :id => 143489 },
  { :name => 'Denmark',              :id => 143458 },
  { :name => 'Deutschland',          :id => 143443 },
  { :name => 'El Salvador',          :id => 143506 },
  { :name => 'Espana',               :id => 143454 },
  { :name => 'Finland',              :id => 143447 },
  { :name => 'France',               :id => 143442 },
  { :name => 'Greece',               :id => 143448 },
  { :name => 'Guatemala',            :id => 143504 },
  { :name => 'Hong Kong',            :id => 143463 },
  { :name => 'Hungary',              :id => 143482 },
  { :name => 'India',                :id => 143467 },
  { :name => 'Indonesia',            :id => 143476 },
  { :name => 'Ireland',              :id => 143449 },
  { :name => 'Israel',               :id => 143491 },
  { :name => 'Italia',               :id => 143450 },
  { :name => 'Korea',                :id => 143466 },
  { :name => 'Kuwait',               :id => 143493 },
  { :name => 'Lebanon',              :id => 143497 },
  { :name => 'Luxembourg',           :id => 143451 },
  { :name => 'Malaysia',             :id => 143473 },
  { :name => 'Mexico',               :id => 143468 },
  { :name => 'Nederland',            :id => 143452 },
  { :name => 'New Zealand',          :id => 143461 },
  { :name => 'Norway',               :id => 143457 },
  { :name => 'Osterreich',           :id => 143445 },
  { :name => 'Pakistan',             :id => 143477 },
  { :name => 'Panama',               :id => 143485 },
  { :name => 'Peru',                 :id => 143507 },
  { :name => 'Phillipines',          :id => 143474 },
  { :name => 'Poland',               :id => 143478 },
  { :name => 'Portugal',             :id => 143453 },
  { :name => 'Qatar',                :id => 143498 },
  { :name => 'Romania',              :id => 143487 },
  { :name => 'Russia',               :id => 143469 },
  { :name => 'Saudi Arabia',         :id => 143479 },
  { :name => 'Schweiz/Suisse',       :id => 143459 },
  { :name => 'Singapore',            :id => 143464 },
  { :name => 'Slovakia',             :id => 143496 },
  { :name => 'Slovenia',             :id => 143499 },
  { :name => 'South Africa',         :id => 143472 },
  { :name => 'Sri Lanka',            :id => 143486 },
  { :name => 'Sweden',               :id => 143456 },
  { :name => 'Taiwan',               :id => 143470 },
  { :name => 'Thailand',             :id => 143475 },
  { :name => 'Turkey',               :id => 143480 },
  { :name => 'United Arab Emirates', :id => 143481 },
  { :name => 'United Kingdom',       :id => 143444 },
  { :name => 'Venezuela',            :id => 143502 },
  { :name => 'Vietnam',              :id => 143471 },
  { :name => 'Japan',                :id => 143462 },
  { :name => 'Dominican Republic',   :id => 143508 },
  { :name => 'Ecuador',              :id => 143509 },
  { :name => 'Egypt',                :id => 143516 },
  { :name => 'Estonia',              :id => 143518 },
  { :name => 'Honduras',             :id => 143510 },
  { :name => 'Jamaica',              :id => 143511 },
  { :name => 'Kazakhstan',           :id => 143517 },
  { :name => 'Latvia',               :id => 143519 },
  { :name => 'Lithuania',            :id => 143520 },
  { :name => 'Macau',                :id => 143515 },
  { :name => 'Malta',                :id => 143521 },
  { :name => 'Moldova',              :id => 143523 },
  { :name => 'Nicaragua',            :id => 143512 },
  { :name => 'Paraguay',             :id => 143513 },
  { :name => 'Uruguay',              :id => 143514 },
]

# Enable to turn on debugging output
DEBUG = false
# Enable to save the source XML files from the App Store
DEBUG_SAVE_SOURCE_XML = DEBUG && true

##
# Return the current review page number by parsing the page content
def getCurrentPage(doc)
  currentPage = 1

  doc.search("Document > View > ScrollView > VBoxView > View > MatrixView > VBoxView:nth(0) > HBoxView > TextView > SetFontStyle > b").each do |e|
    # Parse the first number in the string, e.g. the 3 in "Page 3 of 99"
    currentPage = e.inner_html[/[0-9]+/].to_i
  end

  return currentPage
end

##
# Return the total number of review pages by parsing the page content
def getNumberOfPages(doc)
  numberOfPages = 1

  doc.search("Document > View > ScrollView > VBoxView > View > MatrixView > VBoxView:nth(0) > HBoxView > TextView > SetFontStyle > b").each do |e|
    # Parse the last number in the string, e.g. the 99 in "Page 3 of 99"
    numberOfPages = e.inner_html[/[0-9]+$/].to_i
  end

  return numberOfPages
end

##
# return a rating/subject/author/body hash
def fetch_reviews(software_id, store, pageNumber=0, *previous)
  reviews = []

  # If passed a list of reviews then use that an add any new ones to it
  if previous.length > 0
    reviews = previous[0]
  end

  # TODO: parameterize type=Purple+Software
  # TODO: parameterize sortOrdering
  #  Valid sortOrdering options are:
  #   0/1 = Most Helpful
  #    2  = Most Favorable
  #    3  = Most Critical
  #    4  = Most Recent
  cmd = sprintf(%{curl -s -A "iTunes/9.2 (Macintosh; U; Mac OS X 10.6" -H "X-Apple-Store-Front: %s-1" } <<
                %{'https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?} <<
                %{sortOrdering=1&type=Purple+Software&mt=8&id=%s&pageNumber=%s' | xmllint --format --recover - 2>/dev/null},
                store[:id],
                software_id,
                pageNumber)

  rawxml = `#{cmd}`


  if defined?(DEBUG) && DEBUG_SAVE_SOURCE_XML == true
    open("appreview.#{software_id}.#{store[:id]}.#{pageNumber}.xml", 'w') { |f| f.write(rawxml) }
  end

  doc = Hpricot.XML(rawxml)

  # Get current page nr
  currentPage = getCurrentPage(doc)
  # Get total number of pages
  numberOfPages = getNumberOfPages(doc)

  doc.search("Document > View > ScrollView > VBoxView > View > MatrixView > VBoxView:nth(0) > VBoxView > VBoxView").each do |e|
    review = {}

    strings = (e/:SetFontStyle)
    meta    = strings[2].inner_text.split(/\n/).map { |x| x.strip }

    # Note: Translate is sensitive to spaces around punctuation, so we make sure br's connote space.
    review[:rating]  = e.inner_html.match(/alt="(\d+) star(s?)"/)[1].to_i
    review[:author]  = meta[3]
    review[:version] = meta[7][/Version (.*)/, 1] unless meta[7].nil?
    review[:date]    = meta[10]
    review[:subject] = strings[0].inner_text.strip
    review[:body]    = strings[3].inner_html.gsub("<br />", "\n").strip

    reviews << review
  end

  # If there are more review pages to go, then go fetch and parse the next one, if not then return the list
  if (pageNumber + 1) < numberOfPages
    fetch_reviews(software_id, store, pageNumber + 1, reviews)
  else
    return reviews
  end
end

##
# Prints the reviews in CSV format
def outputCSV(reviews, store)
  if reviews.any?
    CSV.open("./reviews.csv", "wb") do |csv|
      csv << ["store", "date", "version", "author", "rating", "subject", "review"]
      reviews.each_with_index do |review, index|
        csv << [store[:name], review[:date], review[:version], review[:author], review[:rating], review[:subject], review[:body]]
      end
    end
  end
end

##
# Prints the reviews in the standard format
def outputStandard(reviews, store)
  if reviews.any?
    puts "=== Store: #{store[:name]}"

    reviews.each_with_index do |review, index|
      puts sprintf(%{%s %s, "%s", by %s, for version %s, on %s},
        review[:rating], review[:rating] > 1 ? "stars" : "star", review[:subject],
        review[:author], review[:version], review[:date])
      puts review[:body]
      puts "--\n" if index + 1 < reviews.size
    end
  end
end

##
# A simple command-line presentation
software.keys.sort.each do |software_key|

  stores.sort_by { |a| a[:name] }.each do |store|
    reviews = fetch_reviews(software[software_key], store)
    outputCSV(reviews, store)
  end
end
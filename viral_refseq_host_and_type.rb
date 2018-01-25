# Apparently there is an issue with the BioRuby GB parser handling
# blank lines in the GB file.  I don't know how often this happens or
# if it is a problem, but see https://gist.github.com/radaniba/4170368
# for more info.

require "bio"
require "abort_if"

include AbortIf

# division => PHG, VRL, etc
# natype => dna, rna, etc

infile = ARGV.first

outbase = infile.sub(/.gbff*$/, "")
outf_hosts = outbase + ".hosts.txt"

seq_files = {}
# prot_files = {}

File.open(outf_hosts, "w") do |hosts_f|

  n = 0
  Bio::FlatFile.auto(ARGV.first).each_entry do |gb|
    n += 1
    STDERR.printf("WORKING ON -- #{n}\r") if (n % 100).zero?

    if !seq_files.has_key?(gb.division)
      seq_outf = "#{outbase}.seqs_#{gb.division.downcase}.fa"
      seq_files[gb.division] = File.open(seq_outf, "w")
    end

    # if !prot_files.has_key?(gb.division)
    #   prot_outf = "#{outbase}.prot_#{gb.division.downcase}.fa"
    #   prot_files[gb.division] = File.open(prot_outf, "w")
    # end

    record = ">#{gb.entry_id}\n#{gb.seq.upcase}"
    seq_files[gb.division].puts record

    # Iterate through the proteins
    # gb.each_cds do |cds|
    #   protein_id = ""
    #   translation = ""

    #   info = cds.qualifiers.select { |qual| qual.qualifier == "protein_id" || qual.qualifier == "translation" }
    #   if info.count == 2

    #      info.each do |qual|
    #        if qual.qualifier == "protein_id"
    #          protein_id = qual.qualifier
    #        elsif qual.qualifier == "translation"
    #          translation = qual.qualifier
    #        else
    #          abort_if true,
    #                   "Something went wrong.  Needed protein_id or translation, got #{qual.qualifier}"
    #        end
    #      end

    #     abort_if protein_id.empty?,
    #              "Got no protein_id for #{gb.entry_id}"

    #     abort_if translation.empty?,
    #              "Got no translation for #{gb.entry_id}"

    #     record = ">#{gb.entry_id} #{protein_id}\n#{translation}"
    #     prot_files[gb.division].puts record
    #   else
    #     AbortIf::logger.warn { "No protein translation for #{cds.inspect}" }
    #   end
    # end

    wrote_host = false
    gb.features.each do |feature|
      if feature.feature == "source"
        hosts = feature.qualifiers.select { |qual| qual.qualifier.include? "host" }
        if hosts.count >= 1
          hosts_f.puts [gb.entry_id, gb.natype, gb.division, hosts.map(&:value)].join "\t"
          wrote_host = true
        end

        break # no need to look at the rest of the features.
      end
    end

    unless wrote_host
      hosts_f.puts [gb.entry_id, gb.natype, gb.division, ""].join "\t"
    end
  end
end

seq_files.each  { |_, f| f.close }
# prot_files.each { |_, f| f.close }

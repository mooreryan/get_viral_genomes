#!/usr/bin/env ruby
Signal.trap("PIPE", "EXIT")
require "abort_if"

include AbortIf
include AbortIf::Assert

GB_SEP = "//\n"

infile = ARGV[0]

outbase = infile.sub(/.gpff*$/, "")
info_outf = File.open(outbase + ".info.txt", "w")
seq_outf = File.open(outbase + ".seqs.faa", "w")

# TODO things can run on multiple lines.  DEFINITION will often do it,
# but not sure about the other ones we're actually parsing.

File.open(infile, "rt").each_line(sep=GB_SEP).with_index do |rec, idx|
  STDERR.printf("READING -- #{idx}\r") if (idx % 1000).zero?
  info = {}
  in_seq = false
  seq = ""
  current = ""
  acc_line_idx = -1

  rec.sub!(/\/\/\n$/, "") # remove the trailing //\n
  rec.split("\n").each do |line|
    line.chomp!

    if line.start_with? "LOCUS"
      current = "LOCUS"
      info_line = line.split " "
      abort_unless info_line.count == 7,
                   "This does not look like a GenBank formatted file: #{line.inspect}"

      info[:protein_acc] = info_line[1]
      info[:len] = info_line[2].to_i
      info[:type] = info_line[3] # should be aa
      info[:circular] = info_line[4]
      info[:division] = info_line[5]
      info[:date] = info_line[6]
    elsif line.start_with? "DEFINITION"
      current = "DEFINITION"
      info[:definition] = line.split(" ").drop(1).join(" ")
    elsif line.start_with? "ACCESSION"
      current = "ACCESSION"
      # We've seen the accession line, so we know that the definition
      # is over.
    elsif line.start_with? "DBSOURCE"
      current = "DBSOURCE"
      # Line looks like: DBSOURCE    REFSEQ: accession NC_014126.1
      # We want: NC_014126
      info[:genome_acc] = line.split(" ").last.split(".").first
    elsif line.start_with? "ORIGIN"
      current = "ORIGIN"
      # Once you hit ORIGIN line, then everything else is the sequence
      # until the end.
      in_seq = true
    elsif in_seq
      seq << line.sub(/^.*[0-9]+/, "").tr(" ", "").upcase
    elsif line.start_with? " "
      # TODO: Catch all the things we parse that may go onto multiple
      # lines.  Currently only handling the DEFINITION.
      if current == "DEFINITION"
        info[:definition] << line.sub(/^ +/, "")
      end
    end
  end

  # Done parsing the record.  Spit out the info.
  abort_unless (info[:protein_acc] && info[:genome_acc]),
               "Missing info for #{rec.inspect}"
  abort_if seq.empty?,
           "Missing seq for #{info[:protein_acc]}    #{rec}"

  record = ">#{info[:protein_acc]}\t#{info[:genome_acc]}\t#{info[:division]}\t#{info[:definition]}\n#{seq}"

  seq_outf.puts record

  info_outf.puts [info[:protein_acc], info[:genome_acc], info[:division], info[:definition]].join "\t"
end

info_outf.close
seq_outf.close
